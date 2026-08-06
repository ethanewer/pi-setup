import type { AssistantMessage, Message, ToolResultMessage } from "@earendil-works/pi-ai";

/**
 * Trim the inherited history to something a provider will accept.
 *
 * The point of /btw is that it works *while the main thread is running*, so the snapshot
 * is routinely taken mid-turn: the last assistant message can hold tool calls whose
 * results do not exist yet. Sending that to a provider is an immediate 400. Codex avoids
 * the problem by forking a persisted rollout; here the fix is to cut the history back to
 * the last point where every tool call has its result.
 *
 * This function only fixes tool-call pairing. Sizing it to the window is a separate
 * concern, handled by fitInheritedMessages; see the note there for why an earlier version
 * of this comment was wrong to claim no size cap was needed.
 */
export function sanitizeInheritedMessages(messages: readonly Message[]): Message[] {
	const resolved = new Set<string>();
	for (const message of messages) {
		if (message.role === "toolResult") resolved.add(message.toolCallId);
	}

	let cut = messages.length;
	for (let i = 0; i < messages.length; i++) {
		const message = messages[i];
		if (message.role !== "assistant") continue;
		const calls = toolCallIds(message);
		if (calls.length > 0 && calls.some((id) => !resolved.has(id))) {
			cut = i;
			break;
		}
	}

	return dropOrphanToolResults(messages.slice(0, cut));
}

/**
 * A tool result whose call was cut — or whose call predates a compaction boundary, or was
 * dropped to fit the window — is an orphan, and providers reject those too.
 */
export function dropOrphanToolResults(messages: readonly Message[]): Message[] {
	const indices = new Set(orphanToolResultIndices(messages));
	if (indices.size === 0) return [...messages];
	return messages.filter((_message, index) => !indices.has(index));
}

/** The same rule as an index list, for callers that must splice a live array in place. */
export function orphanToolResultIndices(messages: readonly Message[]): number[] {
	const called = new Set<string>();
	const orphans: number[] = [];
	for (let i = 0; i < messages.length; i++) {
		const message = messages[i];
		if (message.role === "assistant") {
			for (const id of toolCallIds(message)) called.add(id);
		} else if (message.role === "toolResult" && !called.has(message.toolCallId)) {
			orphans.push(i);
		}
	}
	return orphans;
}

function toolCallIds(message: AssistantMessage): string[] {
	const ids: string[] = [];
	for (const part of message.content) {
		if (part.type === "toolCall") ids.push(part.id);
	}
	return ids;
}

/**
 * Token estimation, deliberately not pi-ai's.
 *
 * pi-ai exports `estimateContextTokens` only privately, and it is the wrong function here
 * for two independent reasons.
 *
 * First, it anchors on the last assistant message's reported `usage` and adds only what
 * follows. In a fork, that last assistant message belongs to the *parent*, so the estimate
 * describes the parent's request and is completely insensitive to anything done to the
 * inherited array — measured on a real 797-message session, dropping the oldest half moved
 * the estimate by exactly zero tokens. Trimming against it could never have worked.
 *
 * Second, it assumes shapes real sessions violate: a `compactionSummary` message carries
 * `summary` rather than `content`, and a `custom` message's content can be a plain string,
 * which it iterates character by character until it throws. It survives in Pi only because
 * the usage anchor short-circuits before it reaches either.
 *
 * So this is a plain sum over messages using pi-ai's own chars-per-token constants, with
 * every unknown shape costed rather than crashed on. It is an estimate used to decide
 * trimming, not an accounting figure.
 *
 * Note there are two different estimators in play, and the distinction is the reason this
 * one mirrors pi-ai rather than Pi. `pi-coding-agent` exports its own `estimateTokens`,
 * which is a `switch` over every role and handles all of the above safely — that is the
 * one `pi-codex-compaction` injects, and it is unaffected by any of this. But the
 * function that decides the output budget is pi-ai's, so pi-ai's is the behaviour worth
 * predicting here. Importing either would also cost `bun test tests/` its independence
 * from an installed Pi, which the suite is deliberately built to run without.
 */
const CHARS_PER_TOKEN = 4;
const ESTIMATED_IMAGE_CHARS = 4800;

function jsonLength(value: unknown): number {
	try {
		return (JSON.stringify(value) ?? "undefined").length;
	} catch {
		return 0;
	}
}

function contentChars(content: unknown): number {
	if (typeof content === "string") return content.length;
	if (!Array.isArray(content)) return content === undefined || content === null ? 0 : jsonLength(content);
	let chars = 0;
	for (const block of content) {
		if (typeof block === "string") {
			chars += block.length;
			continue;
		}
		if (!block || typeof block !== "object") continue;
		const part = block as Record<string, unknown>;
		if (typeof part.text === "string") chars += part.text.length;
		else if (typeof part.thinking === "string") chars += part.thinking.length;
		else if (part.type === "image") chars += ESTIMATED_IMAGE_CHARS;
		else if (typeof part.name === "string") chars += part.name.length + jsonLength(part.arguments);
		else chars += jsonLength(part);
	}
	return chars;
}

export function estimateTextTokens(text: string): number {
	return Math.ceil(text.length / CHARS_PER_TOKEN);
}

export function estimateMessageTokens(message: Message): number {
	const record = message as unknown as Record<string, unknown>;
	// compactionSummary keeps its text in `summary`.
	if (record.content === undefined && typeof record.summary === "string") {
		return Math.ceil(record.summary.length / CHARS_PER_TOKEN);
	}
	return Math.ceil(contentChars(record.content) / CHARS_PER_TOKEN);
}

export function estimateMessagesTokens(messages: readonly Message[]): number {
	let total = 0;
	for (const message of messages) total += estimateMessageTokens(message);
	return total;
}

const ZERO_USAGE = {
	input: 0,
	output: 0,
	cacheRead: 0,
	cacheWrite: 0,
	totalTokens: 0,
	cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
};

/**
 * Forget what the parent's requests cost.
 *
 * Pi sizes `max_tokens` as `contextWindow - estimateContextTokens(context) - 4096`, and
 * that estimate anchors on the newest assistant `usage` it can find. Inherited verbatim,
 * the parent's number decides the side thread's output budget — so a parent sitting at
 * 268k of a 272k window leaves the side thread a few hundred tokens to answer in, which
 * its reasoning then spends before writing a word. That is the /btw truncation bug.
 *
 * The inherited figures are wrong for the fork in both directions, which is why they are
 * cleared rather than adjusted: they describe a request built from the parent's system
 * prompt and tools, and under pi-codex-compaction they describe the *folded* request,
 * which is smaller than the history actually being inherited.
 *
 * Zeroing makes Pi fall back to summing the messages it is really about to send. It also
 * makes the side thread's cost display start at zero, which is correct: the fork has not
 * spent anything yet.
 */
export function neutralizeInheritedUsage(messages: readonly Message[]): Message[] {
	return messages.map((message) =>
		message.role === "assistant" && (message as AssistantMessage).usage
			? ({ ...message, usage: { ...ZERO_USAGE } } as Message)
			: message,
	);
}

/** Mirrors pi-ai's CONTEXT_SAFETY_TOKENS, subtracted before `max_tokens` is derived. */
export const SIDE_CONTEXT_SAFETY_TOKENS = 4096;
/** Output budget the side thread insists on keeping for reasoning plus an answer. */
export const SIDE_OUTPUT_RESERVE_TOKENS = 32768;
/** ...but never more than this share of a small model's window, or nothing would be left. */
export const SIDE_OUTPUT_RESERVE_MAX_FRACTION = 0.35;
const MIN_OUTPUT_RESERVE_TOKENS = 1024;

export function sideOutputReserve(contextWindow: number): number {
	if (!Number.isFinite(contextWindow) || contextWindow <= 0) return SIDE_OUTPUT_RESERVE_TOKENS;
	return Math.max(
		MIN_OUTPUT_RESERVE_TOKENS,
		Math.min(SIDE_OUTPUT_RESERVE_TOKENS, Math.floor(contextWindow * SIDE_OUTPUT_RESERVE_MAX_FRACTION)),
	);
}

/**
 * How many tokens of conversation the side thread may hold.
 *
 * `overheadTokens` is the system prompt plus tool schemas, which count against the window
 * but are not messages and cannot be trimmed.
 */
export function sideHistoryBudget(contextWindow: number, overheadTokens: number): number {
	if (!Number.isFinite(contextWindow) || contextWindow <= 0) return Number.POSITIVE_INFINITY;
	const reserve = sideOutputReserve(contextWindow);
	return Math.max(0, contextWindow - SIDE_CONTEXT_SAFETY_TOKENS - reserve - Math.max(0, overheadTokens));
}

/**
 * Drop the oldest inherited messages until the rest fits the budget.
 *
 * Oldest-first, like Codex's own overflow handling: the recent end of a conversation is
 * what a follow-up question is usually about. An answer given from a trimmed history is
 * worth more than no answer at all, but the user is told it happened — the view says so —
 * because a silently shortened context looks like the model forgetting.
 */
export function fitInheritedMessages(
	messages: readonly Message[],
	budgetTokens: number,
): { messages: Message[]; dropped: number } {
	if (!Number.isFinite(budgetTokens)) return { messages: [...messages], dropped: 0 };
	if (budgetTokens <= 0) return { messages: [], dropped: messages.length };

	let total = estimateMessagesTokens(messages);
	if (total <= budgetTokens) return { messages: [...messages], dropped: 0 };

	let start = 0;
	while (start < messages.length && total > budgetTokens) {
		total -= estimateMessageTokens(messages[start]);
		start += 1;
	}
	const kept = dropOrphanToolResults(messages.slice(start));
	return { messages: kept, dropped: messages.length - kept.length };
}

/** Text of the last assistant message, which is the side thread's answer. */
export function lastAssistantText(messages: readonly Message[]): string {
	for (let i = messages.length - 1; i >= 0; i--) {
		const message = messages[i];
		if (message.role !== "assistant") continue;
		const text = assistantText(message);
		if (text.length > 0) return text;
	}
	return "";
}

export function assistantText(message: AssistantMessage): string {
	const parts: string[] = [];
	for (const part of message.content) {
		if (part.type === "text" && typeof part.text === "string") parts.push(part.text);
	}
	return parts.join("").trim();
}

/**
 * Pi's resource loader appends the current date and cwd to the system prompt it builds.
 * The side thread reuses the parent's already-built prompt, so those lines would be
 * appended a second time; strip the ones we can recognise. A miss is cosmetic.
 */
export function stripDynamicSystemPromptFooter(systemPrompt: string): string {
	return systemPrompt
		.replace(/\nCurrent date and time:[^\n]*(?:\nCurrent working directory:[^\n]*)?$/u, "")
		.replace(/\nCurrent working directory:[^\n]*$/u, "")
		.trim();
}

/** Tool result messages, exposed for tests. */
export function isToolResult(message: Message): message is ToolResultMessage {
	return message.role === "toolResult";
}
