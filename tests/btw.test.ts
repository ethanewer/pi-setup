import { describe, expect, test } from "bun:test";
import type { AssistantMessage, Message, ToolResultMessage, UserMessage } from "@earendil-works/pi-ai";

/**
 * `bun test tests/` is pure logic with no installed dependencies, so Pi itself is loaded
 * only if it happens to be resolvable. When it is — a developer machine, or after
 * install.sh — the contract test below runs against the real Pi; otherwise it is skipped
 * rather than failing a suite that is meant to need nothing.
 */
const piCodingAgent = await (async () => {
	try {
		return (await import("@earendil-works/pi-coding-agent")) as { convertToLlm: (m: unknown[]) => unknown[] };
	} catch {
		return undefined;
	}
})();

import {
	estimateMessagesTokens,
	fitInheritedMessages,
	lastAssistantText,
	neutralizeInheritedUsage,
	orphanToolResultIndices,
	sanitizeInheritedMessages,
	SIDE_CONTEXT_SAFETY_TOKENS,
	sideHistoryBudget,
	sideOutputReserve,
	stripDynamicSystemPromptFooter,
} from "../forks/pi-btw-side/extensions/btw/context.js";
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

/**
 * Sizing the fork to the window.
 *
 * The bug these cover: `/btw` forked a parent sitting near the top of its context window,
 * Pi derived `max_tokens` as `contextWindow - contextTokens - 4096`, and the side thread
 * was left a few hundred output tokens — which its reasoning spent before writing an
 * answer. Every reply came back cut off mid-sentence with "reached the maximum output
 * token limit". Measured on the session that produced the report: every truncated turn in
 * the parent sat between 267.9k and 269.1k against a 272k window.
 */
describe("token estimation", () => {
	test("survives the message shapes real sessions contain", () => {
		// pi-ai's own estimator throws on both of these. It gets away with it only because
		// its usage anchor short-circuits before reaching them.
		const compactionSummary = { role: "compactionSummary", summary: "x".repeat(400), timestamp: 0 } as unknown as Message;
		const custom = { role: "custom", content: "y".repeat(400), timestamp: 0 } as unknown as Message;
		expect(estimateMessagesTokens([compactionSummary])).toBe(100);
		expect(estimateMessagesTokens([custom])).toBe(100);
	});

	test("costs thinking and tool-call blocks, not just text", () => {
		const thinking = assistant([{ type: "thinking", thinking: "z".repeat(80) }] as never);
		expect(estimateMessagesTokens([thinking])).toBe(20);
		expect(estimateMessagesTokens([assistant([{ type: "toolCall", id: "a", name: "read", arguments: {} }])])).toBeGreaterThan(0);
	});

	test("is sensitive to trimming — the property pi-ai's estimator lacks", () => {
		const messages: Message[] = [user("a".repeat(4000)), user("b".repeat(4000))];
		expect(estimateMessagesTokens(messages)).toBe(2000);
		expect(estimateMessagesTokens(messages.slice(1))).toBe(1000);
	});
});

describe("neutralizeInheritedUsage", () => {
	test("clears the parent's usage so the fork measures itself", () => {
		const spent = assistant([{ type: "text", text: "hi" }]);
		(spent as { usage: Record<string, number> }).usage = {
			input: 268_000,
			output: 100,
			cacheRead: 0,
			cacheWrite: 0,
			totalTokens: 268_100,
			cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
		} as never;
		const out = neutralizeInheritedUsage([spent]);
		expect((out[0] as AssistantMessage).usage.totalTokens).toBe(0);
		expect((out[0] as AssistantMessage).usage.input).toBe(0);
		// The input array is not mutated: it is Pi's, and the parent still needs its numbers.
		expect((spent as AssistantMessage).usage.totalTokens).toBe(268_100);
	});

	test("leaves non-assistant messages alone", () => {
		const messages: Message[] = [user("hi"), toolResult("a")];
		expect(neutralizeInheritedUsage(messages)).toEqual(messages);
	});
});

describe("sideHistoryBudget", () => {
	test("guarantees a real output budget on a large window", () => {
		const contextWindow = 272_000;
		const budget = sideHistoryBudget(contextWindow, 10_000);
		expect(sideOutputReserve(contextWindow)).toBe(32_768);
		expect(budget).toBe(272_000 - SIDE_CONTEXT_SAFETY_TOKENS - 32_768 - 10_000);
	});

	test("caps the reserve by share of window, so a small model keeps usable history", () => {
		// A flat 32k reserve would leave nothing at all here.
		expect(sideOutputReserve(32_000)).toBe(11_200);
		expect(sideHistoryBudget(32_000, 2_000)).toBeGreaterThan(0);
	});

	test("never goes negative, however large the overhead", () => {
		expect(sideHistoryBudget(8_000, 999_999)).toBe(0);
	});

	test("an unknown window disables trimming rather than guessing", () => {
		expect(sideHistoryBudget(0, 0)).toBe(Number.POSITIVE_INFINITY);
	});
});

describe("fitInheritedMessages", () => {
	test("a parent that already fits is untouched", () => {
		const messages: Message[] = [user("hi"), assistant([{ type: "text", text: "hello" }])];
		const out = fitInheritedMessages(messages, 1000);
		expect(out.dropped).toBe(0);
		expect(out.messages).toEqual(messages);
	});

	test("drops the oldest messages until the rest fits", () => {
		// 250 tokens each.
		const messages: Message[] = [user("a".repeat(1000)), user("b".repeat(1000)), user("c".repeat(1000))];
		const out = fitInheritedMessages(messages, 500);
		expect(out.dropped).toBe(1);
		expect(estimateMessagesTokens(out.messages)).toBeLessThanOrEqual(500);
		// Oldest-first: the recent end is what a follow-up question is about.
		expect(out.messages[out.messages.length - 1]).toEqual(messages[2]);
	});

	test("does not strand a tool result whose call was just dropped", () => {
		const messages: Message[] = [
			assistant([{ type: "toolCall", id: "a", name: "read", arguments: { path: "x".repeat(1000) } }]),
			toolResult("a"),
			user("c".repeat(1000)),
		];
		const out = fitInheritedMessages(messages, 260);
		expect(orphanToolResultIndices(out.messages)).toEqual([]);
		expect(out.messages.some((m) => m.role === "toolResult")).toBe(false);
		// dropped counts the orphan too, so the notice matches what was really removed.
		expect(out.dropped).toBe(2);
	});

	test("a zero budget drops everything rather than sending an oversized request", () => {
		const messages: Message[] = [user("hi"), user("there")];
		expect(fitInheritedMessages(messages, 0)).toEqual({ messages: [], dropped: 2 });
	});

	test("an infinite budget is a no-op", () => {
		const messages: Message[] = [user("hi")];
		expect(fitInheritedMessages(messages, Number.POSITIVE_INFINITY).dropped).toBe(0);
	});

	test("regression: a parent near the top of its window still leaves room to answer", () => {
		const contextWindow = 272_000;
		const overhead = 12_000;
		// 268k of inherited history, the size at which every parent turn was truncated.
		const parent: Message[] = Array.from({ length: 268 }, (_, i) => user(`${i}`.padEnd(4000, "x")));
		expect(estimateMessagesTokens(parent)).toBe(268_000);

		const fitted = fitInheritedMessages(parent, sideHistoryBudget(contextWindow, overhead));
		expect(fitted.dropped).toBeGreaterThan(0);

		// Pi's own formula, from pi-ai's clampMaxTokensToContext.
		const available = contextWindow - (overhead + estimateMessagesTokens(fitted.messages)) - SIDE_CONTEXT_SAFETY_TOKENS;
		expect(available).toBeGreaterThanOrEqual(sideOutputReserve(contextWindow));
	});
});

describe.if(piCodingAgent !== undefined)("inherited history is flattened before it is seeded", () => {
	test("convertToLlm removes every shape Pi's own estimator cannot cost", () => {
		const convertToLlm = piCodingAgent!.convertToLlm;
		// Contract test against the installed Pi. The fork seeds convertToLlm output rather
		// than raw session messages, because clearing the inherited usage stops Pi's
		// estimator short-circuiting past `compactionSummary` (text in `summary`, no
		// `content`) and `custom` (content may be a bare string) — on which it throws.
		const raw = [
			{ role: "compactionSummary", summary: "what came before", tokensBefore: 1, timestamp: 0 },
			{ role: "custom", customType: "monitor", content: "heartbeat", display: true, timestamp: 0 },
			user("hi"),
			assistant([{ type: "text", text: "hello" }]),
		];
		const out = convertToLlm(raw as never) as unknown as Message[];
		expect(out).toHaveLength(4);
		expect(out.every((m) => m.role === "user" || m.role === "assistant" || m.role === "toolResult")).toBe(true);
		expect(out.every((m) => Array.isArray((m as { content?: unknown }).content))).toBe(true);
		expect(estimateMessagesTokens(out)).toBeGreaterThan(0);
		// The summary text survives the conversion; it is the whole value of a compacted parent.
		expect(JSON.stringify(out)).toContain("what came before");
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
