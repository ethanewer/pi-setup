import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, mock, test } from "bun:test";
import { existsSync, mkdtempSync, rmSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

/**
 * The error-resume backoff, asserted on the wiring rather than the arithmetic. A mock Pi
 * drives the real extension: agent_end/agent_settled schedule the wait, agent_start drops
 * it (a review found the first clear sitting in agent_end, which fires only after a run
 * *finishes* — the stale resume steered "continue where you left off" into the middle of
 * the user's next run), session_shutdown and session_start drop it too, and the delayed
 * firing path re-checks idleness so a run the extension never saw begin still cannot be
 * steered. The compacted rescue is pinned with its real ctx — mid-run, isIdle() false —
 * because a re-review found an idleness guard shared by every send had silently killed
 * that path, the cheapest and production-observed one.
 */

// The fork has no node_modules of its own; resolve the real Pi package from Bun's global
// tree so this mock cannot shadow the real modules other suites in the same run load. The
// stub is only for a machine without Pi installed, and nothing in these tests calls it.
const bunGlobal = join(process.env.BUN_INSTALL ?? join(homedir(), ".bun"), "install/global/node_modules/@earendil-works");
const codingAgentEntry = join(bunGlobal, "pi-coding-agent/dist/index.js");
const hasPi = existsSync(codingAgentEntry);
const notInstalled = () => {
	throw new Error("pi-coding-agent is not installed; this suite needs the real extension");
};
mock.module("@earendil-works/pi-coding-agent", () =>
	hasPi
		? require(codingAgentEntry)
		: {
				compact: notInstalled,
				calculateContextTokens: notInstalled,
				convertToLlm: notInstalled,
				estimateTokens: notInstalled,
				generateSummary: notInstalled,
			},
);

type Handler = (event?: unknown, ctx?: unknown) => unknown;

const sent: Array<{ content: string; options: { triggerTurn?: boolean; deliverAs?: string } }> = [];
const handlers = new Map<string, Handler[]>();

// Both halves subscribe to some of the same events (agent_end, session_start,
// session_compact); Pi dispatches them in registration order, so the mock keeps lists.
// registerCommand (the fold half's /context-handoff) and appendEntry (a fold being saved)
// are never exercised by these tests and stay no-ops.
const pi = {
	on(event: string, handler: Handler) {
		const list = handlers.get(event) ?? [];
		list.push(handler);
		handlers.set(event, list);
	},
	sendMessage(message: { content: string }, options: unknown) {
		sent.push({ content: message.content, options: (options ?? {}) as { triggerTurn?: boolean; deliverAs?: string } });
	},
	registerCommand: () => {},
	appendEntry: () => {},
} as unknown as Parameters<typeof import("../forks/pi-context-handoff/extensions/context-handoff/index").default>[0];

const { default: contextHandoffExtension } = await import("../forks/pi-context-handoff/extensions/context-handoff/index");
const { RESUME_TEXTS } = await import("../forks/pi-context-handoff/extensions/context-handoff/resume");

contextHandoffExtension(pi);

const run = (event: string, ev?: unknown, ctx?: unknown): void => {
	for (const handler of handlers.get(event) ?? []) void handler(ev, ctx);
};

/** The settle event's ctx is what the delayed fire closes over: idleness must be mutable. */
const settleCtx = (idle: { value: boolean }) =>
	({ signal: { aborted: false }, isIdle: () => idle.value, ui: { notify: () => {} } }) as never;

const settleError = (ctx: unknown): void => {
	run("agent_end", { messages: [{ role: "assistant", stopReason: "error" }] }, { signal: { aborted: false } });
	run("agent_settled", undefined, ctx);
};

// Timers are faked synchronously: a scheduled wait is observable (its exact delay is the
// wiring assertion), fireDue() is the deadline passing, and a cleared or fired timer is no
// longer scheduled.
type FakeTimer = { fire: () => void; cleared: boolean; done: boolean; delay: number };
let timers: FakeTimer[] = [];
const realSetTimeout = globalThis.setTimeout;
const realClearTimeout = globalThis.clearTimeout;

beforeEach(() => {
	sent.length = 0;
	timers = [];
	globalThis.setTimeout = ((callback: () => void, delay?: number) => {
		const timer: FakeTimer = { fire: () => callback(), cleared: false, done: false, delay: delay ?? 0 };
		timers.push(timer);
		return timer as unknown as ReturnType<typeof setTimeout>;
	}) as unknown as typeof globalThis.setTimeout;
	globalThis.clearTimeout = ((handle: unknown) => {
		for (const timer of timers) if (timer === handle) timer.cleared = true;
	}) as unknown as typeof globalThis.clearTimeout;
});

afterEach(() => {
	globalThis.setTimeout = realSetTimeout;
	globalThis.clearTimeout = realClearTimeout;
});

const fireDue = (): void => {
	for (const timer of [...timers]) {
		if (timer.cleared || timer.done) continue;
		timer.done = true;
		timer.fire();
	}
};
const pendingDelays = (): number[] =>
	timers.filter((timer) => !timer.cleared && !timer.done).map((timer) => timer.delay);

// The config read resolves through PI_CODING_AGENT_DIR; a temp dir with no config file
// gives the defaults, so resume is on and nothing user-specific leaks into the suite.
let agentDir: string | undefined;
const realAgentDir = process.env.PI_CODING_AGENT_DIR;

beforeAll(() => {
	agentDir = mkdtempSync(join(process.env.TMPDIR ?? "/tmp", "pi-handoff-wiring-"));
	process.env.PI_CODING_AGENT_DIR = agentDir;
});

afterAll(() => {
	if (agentDir) rmSync(agentDir, { recursive: true, force: true });
	if (realAgentDir === undefined) delete process.env.PI_CODING_AGENT_DIR;
	else process.env.PI_CODING_AGENT_DIR = realAgentDir;
});

describe("error-resume backoff wiring", () => {
	test("a compacted resume sends mid-run — the run that compacted is the one it continues", () => {
		// session_compact is emitted from inside the run's own post-run handling, with the
		// run still active (isIdle() false exactly there): the rescue has to be queued at
		// that moment so hasQueuedMessages() carries the run on. An idleness guard shared by
		// every send dropped it; this pins the path with its real, busy ctx.
		run("session_start");
		const ctx = settleCtx({ value: false });
		run("session_before_compact", { branchEntries: [{ message: { role: "assistant", stopReason: "length" } }] }, ctx);
		run("session_compact", { reason: "threshold", willRetry: false }, ctx);
		expect(sent.map((message) => message.content)).toEqual([RESUME_TEXTS.compacted]);
		expect(sent[0]?.options).toEqual({ triggerTurn: true, deliverAs: "steer" });
	});

	test("an error settle waits out 10s before the resume is injected", () => {
		run("session_start");
		settleError(settleCtx({ value: true }));
		expect(sent).toEqual([]);
		expect(pendingDelays()).toEqual([10_000]);
		fireDue();
		expect(sent.map((message) => message.content)).toEqual([RESUME_TEXTS.error]);
		expect(sent[0]?.options).toEqual({ triggerTurn: true, deliverAs: "steer" });
	});

	test("a run starting while the wait runs drops the stale resume", () => {
		// The review's reproduced timeline: error settle → the user submits → the timer's
		// deadline arrives mid-run. agent_start is the first moment the new run exists;
		// the old clear in agent_end would have fired only after that run finished.
		run("session_start");
		settleError(settleCtx({ value: true }));
		expect(pendingDelays()).toEqual([10_000]);
		run("agent_start");
		expect(pendingDelays()).toEqual([]);
		fireDue();
		expect(sent).toEqual([]);
		// And the guard is not broken by the drop: the new run's own error still waits —
		// and the wait doubles, because a dropped stale resume is not a healthy turn.
		settleError(settleCtx({ value: true }));
		expect(pendingDelays()).toEqual([20_000]);
	});

	test("a busy session at fire time drops the resume even without an agent_start", () => {
		run("session_start");
		const idle = { value: true };
		settleError(settleCtx(idle));
		idle.value = false; // a run began that the extension never saw
		fireDue();
		expect(sent).toEqual([]);
	});

	test("the wait doubles per consecutive error resume, then gives up with no timer", () => {
		run("session_start");
		const ctx = settleCtx({ value: true });
		for (const [index, delay] of [10_000, 20_000, 40_000].entries()) {
			settleError(ctx);
			expect(pendingDelays()).toEqual([delay]);
			fireDue();
			expect(sent).toHaveLength(index + 1);
		}
		settleError(ctx);
		expect(pendingDelays()).toEqual([]); // the give-up does not wait
		fireDue();
		expect(sent[sent.length - 1]?.content).toContain("Automatic resume stopped");
		expect(sent[sent.length - 1]?.options.triggerTurn).toBe(false);
	});

	test("session shutdown drops a pending resume", () => {
		run("session_start");
		settleError(settleCtx({ value: true }));
		run("session_shutdown");
		expect(pendingDelays()).toEqual([]);
		fireDue();
		expect(sent).toEqual([]);
	});

	test("a new session drops a pending resume from the previous one", () => {
		run("session_start");
		settleError(settleCtx({ value: true }));
		run("session_start");
		expect(pendingDelays()).toEqual([]);
		fireDue();
		expect(sent).toEqual([]);
	});
});
