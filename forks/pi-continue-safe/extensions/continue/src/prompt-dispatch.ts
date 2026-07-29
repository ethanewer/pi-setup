import type { UserMessage } from "@earendil-works/pi-ai";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { CONTINUATION_PROMPT_MARKER } from "./continuation-prompt.ts";

/** Queue the continuation resume prompt safely if the parent agent is still settling. */
export function sendContinuationPrompt(pi: ExtensionAPI, prompt: string): void | Promise<void> {
	return pi.sendUserMessage(prompt, { deliverAs: "followUp" });
}

function isUserMessage(message: unknown): message is UserMessage {
	if (typeof message !== "object" || message === null || !("role" in message) || message.role !== "user") return false;
	if (!("content" in message)) return false;
	return typeof message.content === "string" || Array.isArray(message.content);
}

function isTextContentPart(value: unknown): value is { type: "text"; text: string } {
	return typeof value === "object"
		&& value !== null
		&& "type" in value
		&& value.type === "text"
		&& "text" in value
		&& typeof value.text === "string";
}

function userMessageText(message: UserMessage): string {
	if (typeof message.content === "string") return message.content;
	return message.content
		.filter(isTextContentPart)
		.map((part) => part.text)
		.join("\n");
}

/** Return true for delivered prompt text that carries this package's resume correlation marker. */
export function isContinuationPromptText(text: string, prompt: string): boolean {
	return text === prompt || text.includes(CONTINUATION_PROMPT_MARKER);
}

/** Return true only for the delivered user message that starts the continuation resume turn. */
export function isContinuationPromptUserMessage(message: unknown, prompt: string): boolean {
	return isUserMessage(message) && isContinuationPromptText(userMessageText(message), prompt);
}
