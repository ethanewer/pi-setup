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
 * No size cap is applied. The parent is by construction below its own compaction
 * threshold, so a fork of it plus one question fits the same window.
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

	const kept = messages.slice(0, cut);
	// A tool result whose call was cut — or whose call predates a compaction boundary —
	// is an orphan, and providers reject those too.
	const called = new Set<string>();
	for (const message of kept) {
		if (message.role === "assistant") for (const id of toolCallIds(message)) called.add(id);
	}
	return kept.filter((message) => message.role !== "toolResult" || called.has(message.toolCallId));
}

function toolCallIds(message: AssistantMessage): string[] {
	const ids: string[] = [];
	for (const part of message.content) {
		if (part.type === "toolCall") ids.push(part.id);
	}
	return ids;
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
