import { describe, expect, test } from "bun:test";
import type { AssistantMessage, Message, ToolResultMessage, UserMessage } from "@earendil-works/pi-ai";

import { lastAssistantText, sanitizeInheritedMessages, stripDynamicSystemPromptFooter } from "../forks/pi-btw-side/extensions/btw/context.js";
import { DEFAULT_BTW_CONFIG, parseModelRef } from "../forks/pi-btw-side/extensions/btw/config.js";
import { buildFirstSideMessage, buildSideDeveloperInstructions, SIDE_BOUNDARY_PROMPT } from "../forks/pi-btw-side/extensions/btw/instructions.js";

const user = (text: string): UserMessage => ({ role: "user", content: [{ type: "text", text }], timestamp: 0 });

const assistant = (parts: Array<{ type: "text"; text: string } | { type: "toolCall"; id: string; name: string; arguments: Record<string, unknown> }>): AssistantMessage =>
	({
		role: "assistant",
		content: parts,
		api: "responses",
		provider: "openai",
		model: "test",
		usage: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, totalTokens: 0, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } },
		stopReason: "stop",
		timestamp: 0,
	}) as AssistantMessage;

const toolResult = (id: string): ToolResultMessage => ({
	role: "toolResult",
	toolCallId: id,
	toolName: "read",
	content: [{ type: "text", text: "ok" }],
	isError: false,
	timestamp: 0,
});

describe("sanitizeInheritedMessages", () => {
	test("keeps a complete conversation untouched", () => {
		const messages: Message[] = [user("hi"), assistant([{ type: "text", text: "hello" }])];
		expect(sanitizeInheritedMessages(messages)).toEqual(messages);
	});

	test("keeps a resolved tool call", () => {
		const messages: Message[] = [
			user("read it"),
			assistant([{ type: "toolCall", id: "a", name: "read", arguments: {} }]),
			toolResult("a"),
			assistant([{ type: "text", text: "done" }]),
		];
		expect(sanitizeInheritedMessages(messages)).toHaveLength(4);
	});

	test("drops a trailing tool call with no result — the mid-turn snapshot case", () => {
		const messages: Message[] = [
			user("read it"),
			assistant([{ type: "text", text: "on it" }]),
			assistant([{ type: "toolCall", id: "pending", name: "read", arguments: {} }]),
		];
		const out = sanitizeInheritedMessages(messages);
		expect(out).toHaveLength(2);
		expect(out.at(-1)).toEqual(messages[1]);
	});

	test("drops everything after the first unresolved call", () => {
		const messages: Message[] = [
			user("go"),
			assistant([{ type: "toolCall", id: "pending", name: "bash", arguments: {} }]),
			assistant([{ type: "text", text: "orphaned tail" }]),
		];
		expect(sanitizeInheritedMessages(messages)).toEqual([messages[0]]);
	});

	test("drops orphan tool results left by a compaction boundary", () => {
		const messages: Message[] = [toolResult("gone"), user("hi"), assistant([{ type: "text", text: "hello" }])];
		const out = sanitizeInheritedMessages(messages);
		expect(out.some((m) => m.role === "toolResult")).toBe(false);
		expect(out).toHaveLength(2);
	});

	test("empty history stays empty", () => {
		expect(sanitizeInheritedMessages([])).toEqual([]);
	});
});

describe("lastAssistantText", () => {
	test("returns the final assistant text", () => {
		const messages: Message[] = [assistant([{ type: "text", text: "first" }]), user("more"), assistant([{ type: "text", text: " second " }])];
		expect(lastAssistantText(messages)).toBe("second");
	});

	test("skips a trailing tool-call-only message", () => {
		const messages: Message[] = [
			assistant([{ type: "text", text: "answer" }]),
			assistant([{ type: "toolCall", id: "x", name: "read", arguments: {} }]),
		];
		expect(lastAssistantText(messages)).toBe("answer");
	});

	test("no assistant message yields empty string", () => {
		expect(lastAssistantText([user("hi")])).toBe("");
	});
});

describe("stripDynamicSystemPromptFooter", () => {
	test("removes the appended date and cwd lines", () => {
		const prompt = "You are pi.\n\nCurrent date and time: 2026-07-30\nCurrent working directory: /tmp";
		expect(stripDynamicSystemPromptFooter(prompt)).toBe("You are pi.");
	});

	test("leaves a prompt without the footer alone", () => {
		expect(stripDynamicSystemPromptFooter("You are pi.")).toBe("You are pi.");
	});
});

describe("instructions", () => {
	test("the first message carries Codex's boundary ahead of the question", () => {
		const message = buildFirstSideMessage("why is this slow?");
		expect(message.startsWith(SIDE_BOUNDARY_PROMPT)).toBe(true);
		expect(message.endsWith("why is this slow?")).toBe(true);
		expect(message).toContain("reference context only");
	});

	test("developer instructions name the tools that actually exist", () => {
		const text = buildSideDeveloperInstructions(["read", "grep"]);
		expect(text).toContain("read, grep");
		expect(text).toContain("side conversation, not the main thread");
	});

	test("a toolless side thread is told so explicitly", () => {
		expect(buildSideDeveloperInstructions([])).toContain("No tools are available");
	});
});

describe("config", () => {
	test("model refs split on the first slash only", () => {
		expect(parseModelRef("openai/gpt-5.6-sol")).toEqual({ provider: "openai", id: "gpt-5.6-sol" });
		expect(parseModelRef("openrouter/anthropic/claude")).toEqual({ provider: "openrouter", id: "anthropic/claude" });
	});

	test("malformed model refs are ignored rather than fatal", () => {
		expect(parseModelRef("gpt-5.6-sol")).toBeNull();
		expect(parseModelRef("/leading")).toBeNull();
		expect(parseModelRef("trailing/")).toBeNull();
		expect(parseModelRef(42)).toBeNull();
	});

	test("defaults are the safe ones", () => {
		expect(DEFAULT_BTW_CONFIG.toolset).toBe("readonly");
		expect(DEFAULT_BTW_CONFIG.enabled).toBe(true);
		// Codex discards a side conversation on exit; leaving a card behind is opt-in.
		expect(DEFAULT_BTW_CONFIG.record).toBe(false);
		expect(DEFAULT_BTW_CONFIG.model).toBeNull();
	});
});
