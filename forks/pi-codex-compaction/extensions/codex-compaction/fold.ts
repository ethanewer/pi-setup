/**
 * Codex-style compaction, as a pure transform over the message list.
 *
 * Why this exists, and why it is shaped like this
 * -----------------------------------------------
 * Codex checks its context budget after *every* sampling request, inside the turn loop,
 * and compacts there (codex-rs/core/src/session/turn.rs:493):
 *
 *     if token_limit_reached && needs_follow_up {
 *         run_auto_compact(..., CompactionPhase::MidTurn).await?;
 *         continue;                       // the turn simply carries on
 *     }
 *
 * Compaction is a *step in the loop*, so the run cannot be lost at a compaction boundary.
 * Pi's `_checkCompaction` is reached only from `_handlePostAgentRun`, after
 * `agent.prompt()` has already returned, so between those two points context grows with no
 * threshold check at all. `ctx.compact()` cannot be used to close the gap: it begins with
 * `_disconnectFromAgent()` and `abort()`, so calling it mid-run kills the run.
 *
 * The one place an extension can intervene inside a run is the `context` hook — "fired
 * before each LLM call, can modify messages" — whose returned array is what the provider
 * actually receives (agent-loop.js:181, `messages = await config.transformContext(...)`).
 * That is the same position in the loop as Codex's check, so this module implements the
 * same decision there.
 *
 * The one structural difference, and it is a real one: this transform is NOT persistent.
 * Codex calls `replace_compacted_history`, which rewrites session state. The `context` hook
 * only shapes one request, so the fold is recomputed and re-applied on every call and the
 * session file keeps the full history. Consequences, all of them deliberate:
 *
 *   - Failure is free. Anything unexpected returns the original array and Pi behaves
 *     exactly as if this package were not installed. Codex, by contrast, ends the turn
 *     when compaction fails (turn.rs:504).
 *   - Nothing is destroyed. A summary that turns out to be poor costs one request, not the
 *     transcript.
 *   - The synthetic messages must be byte-identical on every call or provider prefix
 *     caching breaks. That is why the summary text, the pinned instructions and even the
 *     timestamp are frozen into `FoldState` when the fold is created, and never recomputed.
 *
 * Everything here is pure and injected with its token metrics, so the decisions can be
 * tested without a provider, a session, or a model.
 */

/**
 * Structural view of Pi's `AgentMessage`. Pi does not export that type from the package
 * root (`AgentMessage` appears nowhere in dist/index.d.ts), and the fields used here are
 * the stable ones: `role`, plus `summary` for the two summary roles and `content` for the
 * rest.
 */
export interface MessageLike {
	role: string;
	content?: unknown;
	summary?: string;
	usage?: unknown;
	timestamp?: number;
	[key: string]: unknown;
}

/** Token accounting, injected so this module never imports Pi. */
export interface Metrics {
	/** Pi's own `estimateTokens`, so a message is never costed differently here. */
	estimate: (message: MessageLike) => number;
	/** Pi's own `calculateContextTokens`, for reading a real provider usage record. */
	usageTokens: (usage: unknown) => number;
}

export interface FoldSettings {
	/**
	 * Fraction of the context window at which to fold. Codex derives exactly this and
	 * refuses to let config raise it: `(context_window * 9) / 10`, clamped
	 * (protocol/src/openai_models.rs:310).
	 */
	triggerPercent: number;
	/** Tokens of recent conversation left untouched. Pi's own default is also 20000. */
	keepRecentTokens: number;
	/** Verbatim user-instruction budget. Codex: COMPACT_USER_MESSAGE_MAX_TOKENS = 20_000. */
	pinUserTokens: number;
	/** Below this saving a fold is not worth a summarization request. */
	minSavingTokens: number;
	/**
	 * Stands in for tool schemas, which never appear in `messages` but do appear in every
	 * provider usage number. Without it the estimate path and the usage path would disagree
	 * by a fixed amount and the trigger would drift depending on which one was in play.
	 */
	toolOverheadTokens: number;
}

export const DEFAULT_FOLD_SETTINGS: FoldSettings = {
	triggerPercent: 0.9,
	keepRecentTokens: 20_000,
	pinUserTokens: 20_000,
	minSavingTokens: 4_000,
	toolOverheadTokens: 4_000,
};

/**
 * A fold that has been computed and paid for. Indices are into the *original* message
 * array Pi hands the hook, never into a previously folded view.
 */
export interface FoldState {
	/** `original[0 .. cutIndex)` is represented by `summary` and `pinned`. */
	cutIndex: number;
	summary: string;
	/** Verbatim user instructions rescued from everything folded so far, oldest first. */
	pinned: string[];
	/** Context size at the moment the fold was made; shown in the summary message. */
	tokensBefore: number;
	/** Frozen so the synthetic messages are byte-identical on every subsequent call. */
	timestamp: number;
	/** `original.length` when the fold was made. See `trustUsageFrom`. */
	originalLength: number;
	headFingerprint: string;
	boundaryFingerprint: string;
}

export const PINNED_PREFIX =
	"The user instructions below were part of the conversation that has just been " +
	"compacted, and are reproduced verbatim because a summary paraphrases them. They are a " +
	"record of what has already been asked, not a new request: do not answer them again. " +
	"Use them to check that the work still in progress matches what was actually asked, " +
	"including any constraint or prohibition.\n\n";

/** Codex re-injects real user messages; Pi is not trained on that shape, so they are framed. */
export function pinnedInstructionsText(pinned: readonly string[]): string {
	const body = pinned.map((text) => `<user-instruction>\n${text}\n</user-instruction>`).join("\n\n");
	return `${PINNED_PREFIX}${body}`;
}

/**
 * Roles that may begin a kept tail.
 *
 * Mirrors Pi's own `isCutPointMessage` exactly, including its refusal of `toolResult`:
 * Pi linearizes a tool call so its results immediately follow the assistant message that
 * made them, so cutting anywhere except before a `toolResult` cannot separate the two.
 * Listed explicitly rather than written as `role !== "toolResult"` so that a role added by
 * a future Pi version is not silently assumed to be a safe boundary.
 */
const CUT_POINT_ROLES: readonly string[] = [
	"user",
	"assistant",
	"bashExecution",
	"custom",
	"branchSummary",
	"compactionSummary",
];

export function isCutPoint(message: MessageLike | undefined): boolean {
	return message !== undefined && CUT_POINT_ROLES.includes(message.role);
}

/** Text of a message, best effort, for fingerprinting and for pinning user instructions. */
export function messageText(message: MessageLike | undefined): string {
	if (!message) return "";
	if (typeof message.summary === "string") return message.summary;
	const content = message.content;
	if (typeof content === "string") return content;
	if (!Array.isArray(content)) return "";
	const parts: string[] = [];
	for (const block of content) {
		if (typeof block === "string") {
			parts.push(block);
			continue;
		}
		if (typeof block !== "object" || block === null) continue;
		const item = block as Record<string, unknown>;
		if (typeof item.text === "string") parts.push(item.text);
		else if (typeof item.thinking === "string") parts.push(item.thinking);
		else if (typeof item.name === "string") parts.push(item.name);
	}
	return parts.join("\n");
}

/**
 * Cheap identity for one message.
 *
 * Used to notice that the array a fold was computed against is gone — most often because
 * Pi's own between-runs compaction rewrote history, which replaces the head and renumbers
 * everything. Comparing content rather than only length matters: a rewrite can leave the
 * same count.
 */
export function fingerprint(message: MessageLike | undefined): string {
	if (!message) return "";
	const text = messageText(message);
	return `${message.role}|${message.timestamp ?? 0}|${text.length}|${text.slice(0, 64)}`;
}

/** True when `fold` still describes the array it was computed from. */
export function isFoldValid(original: readonly MessageLike[], fold: FoldState): boolean {
	if (fold.cutIndex <= 0) return false;
	// A fold with nothing after it would send the summary alone and drop the live turn.
	if (original.length <= fold.cutIndex) return false;
	if (fingerprint(original[0]) !== fold.headFingerprint) return false;
	return fingerprint(original[fold.cutIndex - 1]) === fold.boundaryFingerprint;
}

/** How many synthetic messages a fold prepends: the summary, plus pinned instructions. */
export function syntheticCount(fold: FoldState): number {
	return fold.pinned.length > 0 ? 2 : 1;
}

/**
 * The messages to actually send.
 *
 * Order is Pi's, not Codex's. Codex appends the summary *last* because its model is
 * trained to see it there after a mid-turn compaction (compact.rs, `InitialContextInjection`);
 * Pi's native compaction puts the summary first and the retained tail after it, so that is
 * the shape a Pi-configured model already knows.
 */
export function applyFold(original: readonly MessageLike[], fold: FoldState): MessageLike[] {
	const head: MessageLike[] = [
		// Pi's own compaction-summary message type: `convertToLlm` renders it as a user
		// message wrapped in COMPACTION_SUMMARY_PREFIX/SUFFIX, and the TUI already has a
		// renderer for it. `createCompactionSummaryMessage` is not exported from the package
		// root, so the shape is built here; index.ts verifies at runtime that Pi still
		// converts it, and falls back to a plain user message if it ever stops.
		{
			role: "compactionSummary",
			summary: fold.summary,
			tokensBefore: fold.tokensBefore,
			timestamp: fold.timestamp,
		},
	];
	if (fold.pinned.length > 0) {
		head.push({
			role: "user",
			content: [{ type: "text", text: pinnedInstructionsText(fold.pinned) }],
			timestamp: fold.timestamp,
		});
	}
	return [...head, ...original.slice(fold.cutIndex)];
}

/**
 * Fallback shape for the summary, used only if Pi stops converting `compactionSummary`.
 * Deliberately reproduces Pi's own wording so the model sees the same framing either way.
 */
export function plainSummaryMessage(fold: FoldState): MessageLike {
	return {
		role: "user",
		content: [
			{
				type: "text",
				text: `The conversation history before this point was compacted into the following summary:\n\n<summary>\n${fold.summary}\n</summary>`,
			},
		],
		timestamp: fold.timestamp,
	};
}

export interface Measurement {
	tokens: number;
	/** True when a real provider usage record was used rather than an estimate. */
	fromUsage: boolean;
}

/**
 * Size of what would be sent.
 *
 * Prefers a real usage record, exactly as Pi's own `estimateContextTokens` does, but only
 * from an assistant message produced *after* the fold took effect. That restriction is the
 * whole reason `trustUsageFrom` exists: the assistant message that triggered the first fold
 * carries the usage of the huge pre-fold request, and trusting it would make the very next
 * call believe the folded request was still oversized and fold again immediately, throwing
 * away most of the conversation for nothing.
 *
 * `overhead` covers the system prompt and tool schemas, which are in every usage number
 * and in none of the messages. Adding it only on the estimate path is what makes the two
 * paths comparable against one threshold.
 */
export function measure(
	messages: readonly MessageLike[],
	metrics: Metrics,
	options: { trustUsageFrom?: number; overhead?: number } = {},
): Measurement {
	const trustUsageFrom = options.trustUsageFrom ?? 0;
	const overhead = options.overhead ?? 0;
	for (let i = messages.length - 1; i >= trustUsageFrom; i--) {
		const message = messages[i];
		if (message?.role !== "assistant" || message.usage === undefined || message.usage === null) continue;
		const usageTokens = metrics.usageTokens(message.usage);
		if (!Number.isFinite(usageTokens) || usageTokens <= 0) continue;
		let trailing = 0;
		for (let j = i + 1; j < messages.length; j++) trailing += metrics.estimate(messages[j]);
		return { tokens: usageTokens + trailing, fromUsage: true };
	}
	let total = overhead;
	for (const message of messages) total += metrics.estimate(message);
	return { tokens: total, fromUsage: false };
}

/** The index in an applied array from which usage records reflect the current fold. */
export function trustUsageFrom(fold: FoldState | null): number {
	if (!fold) return 0;
	return syntheticCount(fold) + Math.max(0, fold.originalLength - fold.cutIndex);
}

/** Codex: `(context_window * 9) / 10`, and the comparison is `>=`. */
export function triggerTokens(contextWindow: number, triggerPercent: number): number {
	return Math.floor(contextWindow * triggerPercent);
}

export function shouldFold(tokens: number, contextWindow: number, triggerPercent: number): boolean {
	if (!Number.isFinite(contextWindow) || contextWindow <= 0) return false;
	return tokens >= triggerTokens(contextWindow, triggerPercent);
}

/**
 * Where to cut so that roughly `keepRecentTokens` of conversation survives.
 *
 * Same walk as Pi's `findCutPoint`: accumulate backwards from the newest message, and when
 * the budget is passed take the first valid cut point at or after that message. Returns
 * `minIndex` when the budget is never reached, which means "nothing worth folding".
 */
export function findFoldCut(
	messages: readonly MessageLike[],
	keepRecentTokens: number,
	metrics: Metrics,
	minIndex = 0,
): number {
	const cutPoints: number[] = [];
	for (let i = minIndex; i < messages.length; i++) {
		if (isCutPoint(messages[i])) cutPoints.push(i);
	}
	if (cutPoints.length === 0) return minIndex;
	let cut = cutPoints[0];
	let accumulated = 0;
	for (let i = messages.length - 1; i >= minIndex; i--) {
		const tokens = metrics.estimate(messages[i]);
		if (tokens === 0) continue;
		accumulated += tokens;
		if (accumulated < keepRecentTokens) continue;
		for (const candidate of cutPoints) {
			if (candidate >= i) {
				cut = candidate;
				break;
			}
		}
		break;
	}
	return cut;
}

/**
 * Verbatim user instructions from a stretch of history, newest first up to a token budget.
 *
 * Only real `user` messages qualify. `custom` messages also render as user turns — that is
 * how the monitor's events and the context-handoff resume nudge reach the model — but they
 * are machine-generated, and pinning them would spend the budget that exists to protect
 * what the operator actually asked for.
 */
export function collectPinned(
	messages: readonly MessageLike[],
	budgetTokens: number,
	metrics: Metrics,
): string[] {
	if (budgetTokens <= 0) return [];
	const picked: string[] = [];
	let remaining = budgetTokens;
	for (let i = messages.length - 1; i >= 0 && remaining > 0; i--) {
		const message = messages[i];
		if (message?.role !== "user") continue;
		const text = messageText(message).trim();
		if (text.length === 0) continue;
		const tokens = metrics.estimate({ role: "user", content: [{ type: "text", text }], timestamp: 0 });
		if (tokens <= remaining) {
			picked.push(text);
			remaining -= tokens;
			continue;
		}
		// Codex truncates rather than dropping (build_compacted_history_with_limit); the head
		// of an instruction is the part that states the objective.
		const keepChars = Math.max(0, remaining * 4);
		if (keepChars > 0) picked.push(`${text.slice(0, keepChars)}\n… [instruction truncated]`);
		break;
	}
	return picked.reverse();
}

/**
 * Errors that mean "the request was too big", as opposed to any other fault.
 *
 * Codex branches on a typed `CodexErr::ContextWindowExceeded` here and trims only for that
 * one case; a retryable fault gets backoff instead, and `Interrupted` propagates
 * (compact.rs:212-248). Pi's `generateSummary` throws a plain `Error`, so the distinction has
 * to be recovered from the message. Trimming on a rate limit would be pure waste — it would
 * spend the whole trim budget on an error that shrinking cannot fix.
 *
 * These mirror `OVERFLOW_PATTERNS` and `NON_OVERFLOW_PATTERNS` in pi-ai's
 * `utils/overflow.js`, kept short and deliberately not imported: `@earendil-works/pi-ai` does
 * not resolve from an installed extension (verified — Pi injects resolution for its own
 * package only), so importing it would be a load-time failure rather than a fallback.
 */
const SIZE_ERROR_PATTERNS: readonly RegExp[] = [
	/prompt is too long/i,
	/request_too_large/i,
	/input is too long/i,
	/exceeds the context window/i,
	/maximum context length/i,
	/exceeds the maximum/i,
	/maximum prompt length/i,
	/reduce the length of the messages/i,
	/longer than the model'?s context length/i,
	/exceeds the available context size/i,
	/greater than the context length/i,
	/context window exceeds limit/i,
	/exceeded model token limit/i,
	/context[_ ]length[_ ]exceeded/i,
	/too many tokens/i,
	/token limit exceeded/i,
];

/** Checked first: these can match a size pattern while meaning something else entirely. */
const NOT_SIZE_ERROR_PATTERNS: readonly RegExp[] = [/rate limit/i, /too many requests/i, /throttl/i];

export function looksLikeSizeError(error: unknown): boolean {
	const message = error instanceof Error ? error.message : String(error ?? "");
	if (message.length === 0) return false;
	if (NOT_SIZE_ERROR_PATTERNS.some((pattern) => pattern.test(message))) return false;
	return SIZE_ERROR_PATTERNS.some((pattern) => pattern.test(message));
}

/** Existing pins are older than fresh ones; trim from the front when over budget. */
export function mergePinned(
	existing: readonly string[],
	fresh: readonly string[],
	budgetTokens: number,
	metrics: Metrics,
): string[] {
	const merged = [...existing, ...fresh];
	if (budgetTokens <= 0) return [];
	let total = 0;
	const kept: string[] = [];
	for (let i = merged.length - 1; i >= 0; i--) {
		const tokens = metrics.estimate({
			role: "user",
			content: [{ type: "text", text: merged[i] }],
			timestamp: 0,
		});
		if (total + tokens > budgetTokens) break;
		total += tokens;
		kept.push(merged[i]);
	}
	return kept.reverse();
}

export interface FoldPlan {
	/** New `cutIndex` into the original array. */
	cutIndex: number;
	/** The material to summarize: only what is not already covered by `fold.summary`. */
	prefix: MessageLike[];
	pinned: string[];
	tokensBefore: number;
	/** Tokens the fold removes from the request. */
	saving: number;
}

/**
 * Decide how much further to fold, or `null` when it is not worth it.
 *
 * When a fold already exists only the *new* material is summarized; the existing summary is
 * carried into the next one through `generateSummary`'s `previousSummary` argument, which
 * is what that argument is for. Re-summarizing already-summarized text would cost a second
 * pass over it and let detail decay twice.
 */
/** How to choose the cut in an applied array. Injected so the pressure ladder can vary it. */
export type CutSelector = (messages: readonly MessageLike[], minIndex: number) => number;

/**
 * The latest possible cut: fold everything up to the newest valid boundary.
 *
 * Used only as the last rung of the pressure ladder. Note this deliberately does *not* mirror
 * Pi's `findCutPoint`, which keeps everything when no boundary sits after the point where the
 * budget ran out. Pi is right to be conservative because its compaction is destructive; this
 * fold is not, and under pressure folding something beats folding nothing.
 */
export function findLatestCut(messages: readonly MessageLike[], minIndex = 0): number {
	for (let i = messages.length - 1; i >= minIndex; i--) {
		if (isCutPoint(messages[i])) return i;
	}
	return minIndex;
}

export function planFold(
	original: readonly MessageLike[],
	fold: FoldState | null,
	tokensBefore: number,
	settings: FoldSettings,
	metrics: Metrics,
	selectCut?: CutSelector,
): FoldPlan | null {
	const base = fold ? fold.cutIndex : 0;
	const applied = fold ? applyFold(original, fold) : original;
	const synthetic = fold ? syntheticCount(fold) : 0;
	const cutInApplied = selectCut
		? selectCut(applied, synthetic)
		: findFoldCut(applied, settings.keepRecentTokens, metrics, synthetic);
	// At or below the synthetic head there is nothing left to fold: the kept tail is already
	// the whole conversation, and cutting into our own summary would delete it.
	if (cutInApplied <= synthetic) return null;
	const cutIndex = base + (cutInApplied - synthetic);
	if (cutIndex <= base || cutIndex >= original.length) return null;
	const prefix = original.slice(base, cutIndex);
	if (prefix.length === 0) return null;
	let saving = 0;
	for (const message of prefix) saving += metrics.estimate(message);
	if (saving < settings.minSavingTokens) return null;
	const pinned = mergePinned(
		fold?.pinned ?? [],
		collectPinned(prefix, settings.pinUserTokens, metrics),
		settings.pinUserTokens,
		metrics,
	);
	return { cutIndex, prefix, pinned, tokensBefore, saving };
}

/** Reduced tail budgets, tried in turn once pressure is justified; `latest` keeps no tail. */
export const PRESSURE_RUNGS: readonly (number | "latest")[] = [0.5, 0.25, "latest"];

export interface PressuredFoldPlan extends FoldPlan {
	/** Which rung produced it. Anything but the first means the recent tail was sacrificed. */
	rung: number | "latest";
}

/**
 * Fold, giving up the recent tail only when the recent tail is what does not fit.
 *
 * The normal fold is tried first. If it finds nothing, that has two very different causes and
 * conflating them was a real bug, caught in verification:
 *
 *   (a) The whole conversation already fits `keepRecentTokens`, so there is nothing worth
 *       folding. Sacrificing the tail here destroys context to no purpose — and it is
 *       *reachable*: it happened on every call under a deliberately low trigger, folding all
 *       but one message each time and leaving the model to rediscover its task from the
 *       summary. A run doing that can loop.
 *   (b) The tail budget ran out inside a trailing tool result, so no valid boundary follows
 *       and Pi's conservative rule answers "keep everything" while the request stays
 *       oversized. This is the case worth spending the tail on.
 *
 * `trigger` separates them: the estimated size of what a full-budget fold would keep is
 * compared against it, so pressure engages only when the kept material is itself too big. The
 * estimate under-reports slightly, which biases this toward *not* sacrificing the tail — the
 * right direction for a mechanism whose job is to avoid making things worse. Passing `0`
 * disables pressure entirely.
 *
 * Each rung moves toward Codex, which keeps no recent tail at all: its compacted history is
 * initial context, user messages and the summary, nothing else
 * (`build_compacted_history(Vec::new(), ...)`). Keeping a tail is this port's own addition, so
 * surrendering it gives up a divergence rather than a guarantee. `minSavingTokens` is waived
 * too: it exists to avoid paying for a pointless summarization, and once the request will not
 * fit, any saving is worth paying for.
 */
export function planFoldUnderPressure(
	original: readonly MessageLike[],
	fold: FoldState | null,
	tokensBefore: number,
	settings: FoldSettings,
	metrics: Metrics,
	trigger = 0,
): PressuredFoldPlan | null {
	const normal = planFold(original, fold, tokensBefore, settings, metrics);
	if (normal) return { ...normal, rung: 1 };
	if (trigger <= 0) return null;

	const applied = fold ? applyFold(original, fold) : original;
	const synthetic = fold ? syntheticCount(fold) : 0;
	const wouldKeepFrom = findFoldCut(applied, settings.keepRecentTokens, metrics, synthetic);
	let wouldKeepTokens = 0;
	for (let i = wouldKeepFrom; i < applied.length; i++) wouldKeepTokens += metrics.estimate(applied[i]);
	if (wouldKeepTokens < trigger) return null;

	for (const rung of PRESSURE_RUNGS) {
		const tuned: FoldSettings = {
			...settings,
			minSavingTokens: 0,
			keepRecentTokens: rung === "latest" ? 0 : Math.floor(settings.keepRecentTokens * rung),
		};
		const selector: CutSelector | undefined =
			rung === "latest" ? (messages, minIndex) => findLatestCut(messages, minIndex) : undefined;
		const plan = planFold(original, fold, tokensBefore, tuned, metrics, selector);
		if (plan) return { ...plan, rung };
	}
	return null;
}

/**
 * Drop the oldest part of a summarization prefix and resume at a clean boundary.
 *
 * Codex does the same thing when the summarization request itself overflows
 * (compact.rs:215-225, `history.remove_first_item()` in a loop), which is the case Pi has
 * no answer for at all — its compaction either fits or fails. Cutting at a boundary is for
 * readability rather than correctness here: `generateSummary` serializes the prefix to
 * plain text, so a stranded tool result cannot make the request invalid.
 */
export function dropOldest(
	prefix: readonly MessageLike[],
	fraction: number,
	metrics: Metrics,
): MessageLike[] {
	if (prefix.length <= 1) return [...prefix];
	let total = 0;
	for (const message of prefix) total += metrics.estimate(message);
	const target = total * Math.min(Math.max(fraction, 0), 1);
	let removed = 0;
	let index = 0;
	while (index < prefix.length - 1 && removed < target) {
		removed += metrics.estimate(prefix[index]);
		index++;
	}
	while (index < prefix.length - 1 && !isCutPoint(prefix[index])) index++;
	return prefix.slice(index);
}
