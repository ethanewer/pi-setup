import { describe, expect, test } from "bun:test";

import {
	isUnfinishedStop,
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

describe("ResumeGuard aborted-compaction latch", () => {
	test("a cancelled compaction suppresses the agent_settled backstop", () => {
		// Esc during a compaction emits session_compact_failed{aborted:true}, not
		// session_compact. Without the latch the backstop reads the stale "length" that
		// triggered the compaction and resurrects the run the user just stopped.
		const g = new ResumeGuard();
		g.noteCompactionAborted();
		expect(g.decideOnSettled("length")).toBe("ignore");
		expect(g.consecutiveResumes).toBe(0);
	});

	test("the latch is cleared at the next agent boundary, not only at settled", () => {
		// A queued-message continuation runs as another agent loop inside the same
		// agent_settled; the cancel from the previous loop must not suppress its backstop.
		const g = new ResumeGuard();
		g.noteCompactionAborted();
		expect(g.decideOnSettled("length")).toBe("ignore");
		g.noteAgentBoundary();
		expect(g.decideOnSettled("length")).toBe("resume");
	});

	test("endRun also clears the latch", () => {
		const g = new ResumeGuard();
		g.noteCompactionAborted();
		expect(g.decideOnSettled("length")).toBe("ignore");
		g.endRun();
		expect(g.decideOnSettled("length")).toBe("resume");
	});

	test("a cancelled compaction clears the streak, not just suppresses this run", () => {
		// Otherwise a user cancel could leave an old count that hits the give-up cap early.
		const g = new ResumeGuard();
		g.decideOnSettled("error");
		g.endRun();
		g.decideOnSettled("length");
		g.endRun();
		expect(g.consecutiveResumes).toBe(2);
		g.noteCompactionAborted("threshold");
		expect(g.decideOnSettled("length")).toBe("ignore");
		expect(g.consecutiveResumes).toBe(0);
	});

	test("a healthy turn also clears the latch", () => {
		const g = new ResumeGuard();
		g.noteCompactionAborted();
		g.noteHealthyTurn();
		expect(g.decideOnSettled("error")).toBe("resume");
	});

	test("a non-aborted compaction failure still resumes", () => {
		// A thrown/timed-out compaction is exactly what the backstop exists for; only a
		// user cancel must suppress it.
		const g = new ResumeGuard();
		expect(g.decideOnSettled("error")).toBe("resume");
	});

	test("a manual compaction abort does not set the latch", () => {
		// Manual /compact runs outside a run, so no agent_settled would clear the latch and a
		// later legitimate resume would be suppressed.
		const g = new ResumeGuard();
		g.noteCompactionAborted("manual");
		expect(g.decideOnSettled("length")).toBe("resume");
	});

	test("threshold and overflow aborts do set the latch", () => {
		const threshold = new ResumeGuard();
		threshold.noteCompactionAborted("threshold");
		expect(threshold.decideOnSettled("length")).toBe("ignore");

		const overflow = new ResumeGuard();
		overflow.noteCompactionAborted("overflow");
		expect(overflow.decideOnSettled("error")).toBe("ignore");
	});
});

describe("ResumeGuard manual compaction gate", () => {
	test("a manual /compact never resumes, even after a truncation", () => {
		const g = new ResumeGuard();
		expect(g.decide(true, false, "manual")).toBe("ignore");
		expect(g.consecutiveResumes).toBe(0);
	});

	test("a manual compaction does not reset an in-progress resume streak", () => {
		// Otherwise a user running /compact mid-loop would silently buy three more resumes.
		const g = new ResumeGuard();
		g.decide(true, false, "threshold");
		g.endRun();
		expect(g.consecutiveResumes).toBe(1);
		expect(g.decide(true, false, "manual")).toBe("ignore");
		expect(g.consecutiveResumes).toBe(1);
	});

	test("threshold and overflow compactions behave as before", () => {
		const g = new ResumeGuard();
		expect(g.decide(true, false, "threshold")).toBe("resume");
		expect(g.decide(true, false, "overflow")).toBe("resume");
	});
});

describe("isUnfinishedStop", () => {
	test("a deliberate finish and a user cancel are never resumed", () => {
		// Resuming either would talk over the user; these are the two that must stay false.
		expect(isUnfinishedStop("stop")).toBe(false);
		expect(isUnfinishedStop("aborted")).toBe(false);
		expect(isUnfinishedStop(undefined)).toBe(false);
	});

	test("a truncation or a provider error left work unfinished", () => {
		expect(isUnfinishedStop("length")).toBe(true);
		expect(isUnfinishedStop("error")).toBe(true);
	});
});

describe("ResumeGuard backstop on agent_settled", () => {
	test("covers the stops session_compact never sees", () => {
		// A compaction that threw, or nothing-to-compact, emits no session_compact at all.
		const g = new ResumeGuard();
		expect(g.decideOnSettled("error")).toBe("resume");
	});

	test("a normally finished run is left alone", () => {
		const g = new ResumeGuard();
		expect(g.decideOnSettled("stop")).toBe("ignore");
		expect(g.consecutiveResumes).toBe(0);
	});

	test("a cancelled run is left alone", () => {
		const g = new ResumeGuard();
		expect(g.decideOnSettled("aborted")).toBe("ignore");
	});

	test("does not resume twice when session_compact already did", () => {
		const g = new ResumeGuard();
		expect(g.decide(true, false)).toBe("resume");
		expect(g.decideOnSettled("length")).toBe("ignore");
		expect(g.consecutiveResumes).toBe(1);
	});

	test("endRun lets the next run be rescued again", () => {
		const g = new ResumeGuard();
		g.decide(true, false);
		g.endRun();
		expect(g.decideOnSettled("length")).toBe("resume");
		expect(g.consecutiveResumes).toBe(2);
	});

	test("the cap applies across both hooks together", () => {
		const g = new ResumeGuard();
		g.decide(true, false);
		g.endRun();
		g.decideOnSettled("error");
		g.endRun();
		g.decide(true, false);
		g.endRun();
		expect(g.consecutiveResumes).toBe(MAX_CONSECUTIVE_RESUMES);
		expect(g.decideOnSettled("length")).toBe("give-up");
	});

	test("a healthy run between failures resets the cap", () => {
		const g = new ResumeGuard();
		g.decideOnSettled("length");
		g.endRun();
		expect(g.decideOnSettled("stop")).toBe("ignore");
		g.endRun();
		expect(g.consecutiveResumes).toBe(0);
	});
});

describe("ResumeGuard user-abort suppression", () => {
	test("an aborted signal suppresses a stop that settled as error", () => {
		// Live repro 01a091d2: Esc during a `sleep` tool call, tool result "Command aborted",
		// then the post-abort provider call settled as stopReason "error" with errorMessage
		// "The operation was aborted." The old guard read that as unfinished work and resumed
		// the run, so stopping took several Escs.
		const g = new ResumeGuard();
		expect(g.decideOnSettled("error", false, true)).toBe("ignore");
		expect(g.consecutiveResumes).toBe(0);
	});

	test("a real provider error with no abort still resumes", () => {
		const g = new ResumeGuard();
		expect(g.decideOnSettled("error", false, false)).toBe("resume");
	});

	test("a truncation with no abort still resumes", () => {
		const g = new ResumeGuard();
		expect(g.decideOnSettled("length", false, false)).toBe("resume");
	});

	test("an abort clears an in-progress streak rather than leaving it to accumulate", () => {
		const g = new ResumeGuard();
		g.decideOnSettled("error");
		g.endRun();
		expect(g.consecutiveResumes).toBe(1);
		expect(g.decideOnSettled("error", false, true)).toBe("ignore");
		expect(g.consecutiveResumes).toBe(0);
	});

	test("the force-resume test seam still wins over a reported abort", () => {
		const g = new ResumeGuard();
		expect(g.decideOnSettled("stop", true, true)).toBe("resume");
	});
});

describe("ResumeGuard disabled half", () => {
	test("a truncated compaction does not inflate the streak while resume is off", () => {
		// The count must reflect resumes that actually happened, or re-enabling later could
		// start at the give-up cap.
		const g = new ResumeGuard();
		expect(g.decide(true, false, "threshold", false)).toBe("ignore");
		expect(g.consecutiveResumes).toBe(0);
	});

	test("a healthy compaction still clears the streak while resume is off", () => {
		const g = new ResumeGuard();
		g.decide(true, false, "threshold", true);
		g.endRun();
		expect(g.consecutiveResumes).toBe(1);
		expect(g.decide(false, false, "threshold", false)).toBe("ignore");
		expect(g.consecutiveResumes).toBe(0);
	});

	test("reset clears the streak so a new session starts clean", () => {
		const g = new ResumeGuard();
		g.decide(true, false, "threshold");
		g.endRun();
		g.decideOnSettled("error");
		g.endRun();
		expect(g.consecutiveResumes).toBe(2);
		g.reset();
		expect(g.consecutiveResumes).toBe(0);
		// And the latches are gone too.
		expect(g.decideOnSettled("length")).toBe("resume");
	});
});
