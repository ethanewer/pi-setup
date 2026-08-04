import { describe, expect, test } from "bun:test";

import {
	lastAssistantWasTruncated,
	MAX_CONSECUTIVE_RESUMES,
	ResumeGuard,
} from "../forks/pi-context-handoff/extensions/context-handoff/resume";

/**
 * The real signature, taken from sessions 019fcaa8 and 019fcd7f on 2026-08-04: the model
 * was cut off by the context limit, so it produced one empty thinking block, 16 reasoning
 * tokens, and no tool call. Pi's own overflow test misses this because it demands
 * `output === 0`, which is exactly why these cases are checked on stopReason alone.
 */
const truncated = { message: { role: "assistant", stopReason: "length", usage: { output: 16 } } };
const finished = { message: { role: "assistant", stopReason: "stop", usage: { output: 400 } } };
const usedTool = { message: { role: "assistant", stopReason: "toolUse", usage: { output: 209 } } };
const toolResult = { message: { role: "toolResult" } };
const user = { message: { role: "user" } };

describe("lastAssistantWasTruncated", () => {
	test("finds the newest assistant message, not the newest message", () => {
		expect(lastAssistantWasTruncated([user, truncated, toolResult, toolResult])).toBe(true);
		expect(lastAssistantWasTruncated([user, finished, toolResult])).toBe(false);
	});

	test("only a length stop counts as truncation", () => {
		expect(lastAssistantWasTruncated([truncated])).toBe(true);
		expect(lastAssistantWasTruncated([finished])).toBe(false);
		expect(lastAssistantWasTruncated([usedTool])).toBe(false);
	});

	test("an older truncation does not count once a later turn finished", () => {
		expect(lastAssistantWasTruncated([truncated, toolResult, finished])).toBe(false);
	});

	test("survives missing, empty, and malformed input", () => {
		expect(lastAssistantWasTruncated(undefined)).toBe(false);
		expect(lastAssistantWasTruncated([])).toBe(false);
		expect(lastAssistantWasTruncated([{}, { message: null }])).toBe(false);
		expect(lastAssistantWasTruncated([user, toolResult])).toBe(false);
	});

	test("output size is deliberately not part of the test", () => {
		// Requiring output === 0 is the bug being worked around; 16 must still count.
		const zeroOutput = { message: { role: "assistant", stopReason: "length", usage: { output: 0 } } };
		expect(lastAssistantWasTruncated([zeroOutput])).toBe(true);
		expect(lastAssistantWasTruncated([truncated])).toBe(true);
	});
});

describe("ResumeGuard", () => {
	test("a finished turn is never nudged", () => {
		const g = new ResumeGuard();
		expect(g.decide(false, false)).toBe("ignore");
		expect(g.consecutiveResumes).toBe(0);
	});

	test("Pi's own retry path is left alone", () => {
		// willRetry means Pi already returns true and resumes by itself; sending anything
		// here would be a second, redundant nudge.
		const g = new ResumeGuard();
		expect(g.decide(true, true)).toBe("ignore");
	});

	test("a truncation with no Pi retry resumes", () => {
		const g = new ResumeGuard();
		expect(g.decide(true, false)).toBe("resume");
		expect(g.consecutiveResumes).toBe(1);
	});

	test("gives up rather than looping when every resume is truncated again", () => {
		const g = new ResumeGuard();
		for (let i = 0; i < MAX_CONSECUTIVE_RESUMES; i++) {
			expect(g.decide(true, false)).toBe("resume");
		}
		expect(g.decide(true, false)).toBe("give-up");
		// And stays given up rather than oscillating.
		expect(g.decide(true, false)).toBe("give-up");
	});

	test("a healthy turn clears the streak", () => {
		const g = new ResumeGuard();
		g.decide(true, false);
		g.decide(true, false);
		expect(g.consecutiveResumes).toBe(2);
		g.noteHealthyTurn();
		expect(g.consecutiveResumes).toBe(0);
		expect(g.decide(true, false)).toBe("resume");
	});

	test("an ordinary compaction between truncations also clears the streak", () => {
		const g = new ResumeGuard();
		g.decide(true, false);
		expect(g.decide(false, false)).toBe("ignore");
		expect(g.consecutiveResumes).toBe(0);
	});
});
