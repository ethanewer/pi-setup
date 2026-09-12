import { describe, expect, test } from "bun:test";

import {
	boundedSignal,
	createOnceNotifier,
	DEFAULT_SUMMARIZE_TIMEOUT_MS,
	interceptEscape,
	judgeSummary,
	withAuthBaseUrl,
	workingMessageSetter,
} from "../forks/pi-context-handoff/extensions/context-handoff/util";

type Ctx = Parameters<typeof interceptEscape>[0];

/**
 * Wiring tests for the fold/handoff plumbing that `fold.test.ts` cannot reach: `fold-hook.ts`
 * and `index.ts` import Pi's runtime, so their helpers live in `util.ts` and are exercised
 * here. These pin the two behaviours the audit found broken — an unbounded summarization and
 * Esc aborting the whole run during a fold — without needing a provider or a TUI.
 */

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

describe("boundedSignal", () => {
	test("forwards the agent's abort and does not report a timeout", () => {
		const parent = new AbortController();
		const bound = boundedSignal(parent.signal, 60_000);
		try {
			expect(bound.signal.aborted).toBe(false);
			parent.abort(new Error("user cancelled"));
			expect(bound.signal.aborted).toBe(true);
			expect(bound.timedOut()).toBe(false);
		} finally {
			bound.dispose();
		}
	});

	test("a parent that is already aborted is followed immediately", () => {
		const parent = new AbortController();
		parent.abort();
		const bound = boundedSignal(parent.signal, 60_000);
		try {
			expect(bound.signal.aborted).toBe(true);
		} finally {
			bound.dispose();
		}
	});

	test("fires its own deadline and reports it as a timeout", async () => {
		const bound = boundedSignal(undefined, 10);
		try {
			expect(bound.signal.aborted).toBe(false);
			await sleep(25);
			expect(bound.signal.aborted).toBe(true);
			expect(bound.timedOut()).toBe(true);
		} finally {
			bound.dispose();
		}
	});

	test("dispose cancels the deadline so a completed call never fires it", async () => {
		const bound = boundedSignal(undefined, 10);
		bound.dispose();
		await sleep(25);
		expect(bound.signal.aborted).toBe(false);
		expect(bound.timedOut()).toBe(false);
	});

	test("an explicit abort is not a timeout", () => {
		const bound = boundedSignal(undefined, 60_000);
		try {
			bound.abort(new Error("fold cancelled by user"));
			expect(bound.signal.aborted).toBe(true);
			expect(bound.timedOut()).toBe(false);
		} finally {
			bound.dispose();
		}
	});

	test("zero disables the deadline", async () => {
		const bound = boundedSignal(undefined, 0);
		try {
			await sleep(15);
			expect(bound.signal.aborted).toBe(false);
		} finally {
			bound.dispose();
		}
	});

	test("the default is a positive, human-scale bound", () => {
		expect(DEFAULT_SUMMARIZE_TIMEOUT_MS).toBeGreaterThan(60_000);
		expect(DEFAULT_SUMMARIZE_TIMEOUT_MS).toBeLessThanOrEqual(3_600_000);
	});
});

describe("judgeSummary", () => {
	test("discards the text when the deadline fired, even a full-looking summary", () => {
		// Providers resolve an aborted stream with the partial text, so partial and complete
		// are indistinguishable. Accepting it would replace folded history with a fragment.
		expect(judgeSummary({ text: "## Goal\npartial but plausible", timedOut: true, userAborted: false })).toEqual({
			use: false,
			reason: "timed-out",
		});
	});

	test("a user cancel wins over a fired deadline and is never a failure", () => {
		expect(judgeSummary({ text: "partial", timedOut: true, userAborted: true })).toEqual({
			use: false,
			reason: "aborted",
		});
	});

	test("accepts non-empty text when nothing aborted", () => {
		expect(judgeSummary({ text: "  ## Goal\nfinish the job  ", timedOut: false, userAborted: false })).toEqual({
			use: true,
			text: "  ## Goal\nfinish the job  ",
		});
	});

	test("rejects empty, whitespace, and missing text", () => {
		expect(judgeSummary({ text: "", timedOut: false, userAborted: false })).toEqual({
			use: false,
			reason: "empty",
		});
		expect(judgeSummary({ text: "   \n", timedOut: false, userAborted: false })).toEqual({
			use: false,
			reason: "empty",
		});
		expect(judgeSummary({ text: undefined, timedOut: false, userAborted: false })).toEqual({
			use: false,
			reason: "empty",
		});
	});
});

describe("interceptEscape", () => {
	/** A fake UI context that records the installed listener and its unsubscribe. */
	const fakeCtx = (opts: { hasUI?: boolean; onTerminalInput?: boolean } = {}) => {
		const state = {
			handler: undefined as ((data: string) => { consume?: boolean; data?: string } | undefined) | undefined,
			unsubscribed: false,
		};
		const ui: Record<string, unknown> = {};
		if (opts.onTerminalInput !== false) {
			ui.onTerminalInput = (handler: (data: string) => { consume?: boolean; data?: string } | undefined) => {
				state.handler = handler;
				return () => {
					state.unsubscribed = true;
					state.handler = undefined;
				};
			};
		}
		return { ctx: { hasUI: opts.hasUI ?? true, ui } as unknown as Ctx, state };
	};

	test("a lone Escape cancels immediately and is consumed", () => {
		// Pi's StdinBuffer already reassembled any split sequence and held a lone Escape for its
		// own (SSH-scaled) window, so a bare "\x1b" here is a confirmed Escape key.
		const { ctx, state } = fakeCtx();
		let cancelled = 0;
		const escape = interceptEscape(ctx, () => cancelled++);
		try {
			expect(escape.active).toBe(true);
			expect(state.handler?.("\x1b")).toEqual({ consume: true });
			expect(cancelled).toBe(1);
		} finally {
			escape.dispose();
		}
	});

	test("other keys pass through untouched", () => {
		const { ctx, state } = fakeCtx();
		let cancelled = 0;
		const escape = interceptEscape(ctx, () => cancelled++);
		try {
			expect(state.handler?.("a")).toBeUndefined();
			// A reassembled arrow key is one chunk and must not cancel.
			expect(state.handler?.("\x1b[A")).toBeUndefined();
			expect(cancelled).toBe(0);
		} finally {
			escape.dispose();
		}
	});

	test("dispose unsubscribes", () => {
		const { ctx, state } = fakeCtx();
		const escape = interceptEscape(ctx, () => {});
		escape.dispose();
		expect(state.unsubscribed).toBe(true);
		expect(state.handler).toBeUndefined();
	});

	test("is a no-op without a UI or without terminal input support", () => {
		expect(interceptEscape(fakeCtx({ hasUI: false }).ctx, () => {}).active).toBe(false);
		expect(interceptEscape(fakeCtx({ onTerminalInput: false }).ctx, () => {}).active).toBe(false);
	});

	test("a UI that refuses a listener degrades to inactive rather than throwing", () => {
		const ctx = {
			hasUI: true,
			ui: {
				onTerminalInput: () => {
					throw new Error("not available");
				},
			},
		} as unknown as Ctx;
		const escape = interceptEscape(ctx, () => {});
		expect(escape.active).toBe(false);
		escape.dispose();
	});
});

describe("withAuthBaseUrl", () => {
	test("applies the auth-resolved base URL, mirroring Pi's own summarization path", () => {
		const model = { id: "m", provider: "azure", baseUrl: "https://default.example" };
		expect(withAuthBaseUrl(model, "https://deployment.example").baseUrl).toBe("https://deployment.example");
	});

	test("returns the same model when there is no auth base URL", () => {
		const model = { id: "m", provider: "openai" };
		expect(withAuthBaseUrl(model, undefined)).toBe(model);
	});
});

describe("createOnceNotifier", () => {
	const ctxWith = (sink: (message: string) => void) =>
		({ hasUI: true, ui: { notify: (message: string) => sink(message) } }) as unknown as Ctx;

	test("fires once per distinct message and can be reset per session", () => {
		const seen: string[] = [];
		const ctx = ctxWith((message) => seen.push(message));
		const notify = createOnceNotifier();
		notify(ctx, "a", "warning");
		notify(ctx, "a", "warning");
		notify(ctx, "b", "info");
		expect(seen).toEqual(["a", "b"]);
		notify.reset();
		notify(ctx, "a", "warning");
		expect(seen).toEqual(["a", "b", "a"]);
	});

	test("does not consume a message it could not show", () => {
		// A headless run must not burn a warning that a later UI-bearing phase should get.
		const seen: string[] = [];
		const headless = { hasUI: false, ui: {} } as unknown as Ctx;
		const notify = createOnceNotifier();
		notify(headless, "boom", "warning");
		notify(ctxWith((message) => seen.push(message)), "boom", "warning");
		expect(seen).toEqual(["boom"]);
	});
});

describe("workingMessageSetter", () => {
	test("sets and clears the streaming working message", () => {
		const seen: Array<string | undefined> = [];
		const ctx = {
			hasUI: true,
			ui: { setWorkingMessage: (message?: string) => seen.push(message) },
		} as unknown as Ctx;
		workingMessageSetter(ctx, "folding context");
		workingMessageSetter(ctx, undefined);
		expect(seen).toEqual(["folding context", undefined]);
	});

	test("is a no-op without a UI and swallows a refusing UI", () => {
		workingMessageSetter({ hasUI: false, ui: {} } as unknown as Ctx, "x");
		const ctx = {
			hasUI: true,
			ui: {
				setWorkingMessage: () => {
					throw new Error("no working indicator");
				},
			},
		} as unknown as Ctx;
		expect(() => workingMessageSetter(ctx, "x")).not.toThrow();
	});
});
