/**
 * Helpers shared by the handoff and fold halves of this package. These existed in both
 * halves (handoff and fold) as near-identical
 * copies; the merge is what finally gives them a single home.
 */

import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join, resolve } from "node:path";

import type { ExtensionContext } from "@earendil-works/pi-coding-agent";

/** Shape Pi passes to its summarization calls as a retry policy. */
export interface RetryPolicy {
	enabled: boolean;
	maxRetries: number;
	baseDelayMs: number;
}

/**
 * Upper bound on one summarization call, retries included. `completeSimple` does receive
 * Pi's global undici idle timeout (`configureHttpDispatcher` installs bodyTimeout and
 * headersTimeout from `httpIdleTimeoutMs` in every entry mode), but that only fires on
 * inactivity: a stream that keeps slowly producing tokens, or the retry schedule layered on
 * top of it, can run far longer than intended. This is a total-duration cap, so a stalled or
 * merely glacial summarization cannot outlive it. Configurable; 0 disables it.
 */
export const DEFAULT_SUMMARIZE_TIMEOUT_MS = 15 * 60_000;

/**
 * A signal that follows the agent's abort but also fires its own timeout, so a
 * summarization cannot outlive the bound however the provider behaves.
 */
export interface BoundedSignal {
	signal: AbortSignal;
	/** True only when the deadline expired, never for an agent/user abort. */
	timedOut: () => boolean;
	/** Abort for a reason other than the deadline, e.g. the user cancelling the fold. */
	abort: (reason?: unknown) => void;
	dispose: () => void;
}

export function boundedSignal(parent: AbortSignal | undefined, timeoutMs: number): BoundedSignal {
	const controller = new AbortController();
	let timedOut = false;
	const forward = () => controller.abort(parent?.reason);
	if (parent) {
		if (parent.aborted) controller.abort(parent.reason);
		else parent.addEventListener("abort", forward, { once: true });
	}
	const timer =
		Number.isFinite(timeoutMs) && timeoutMs > 0
			? setTimeout(() => {
					timedOut = true;
					controller.abort(new Error("summarization timed out"));
				}, timeoutMs)
			: undefined;
	// Do not hold the process open just for the deadline; dispose() clears it anyway.
	(timer as { unref?: () => void } | undefined)?.unref?.();
	return {
		signal: controller.signal,
		timedOut: () => timedOut,
		abort: (reason) => controller.abort(reason),
		dispose: () => {
			if (timer) clearTimeout(timer);
			parent?.removeEventListener("abort", forward);
		},
	};
}

/**
 * What to do with a summarization result. Providers resolve an aborted stream with the
 * partial text rather than rejecting, so a complete summary and a mid-stream abort are
 * indistinguishable here. That makes the order load-bearing: a fired deadline must discard
 * whatever arrived, however much of it there is, or a truncated fragment would replace the
 * folded-away history (and, for the handoff, be persisted as the session checkpoint).
 */
export type SummaryVerdict =
	| { use: true; text: string }
	| { use: false; reason: "aborted" | "timed-out" | "empty" };

export function judgeSummary(opts: {
	text: string | undefined | null;
	timedOut: boolean;
	userAborted: boolean;
}): SummaryVerdict {
	if (opts.userAborted) return { use: false, reason: "aborted" };
	if (opts.timedOut) return { use: false, reason: "timed-out" };
	if (typeof opts.text === "string" && opts.text.trim().length > 0) return { use: true, text: opts.text };
	return { use: false, reason: "empty" };
}

export interface EscapeInterceptor {
	/** True when a terminal input listener was actually installed. */
	active: boolean;
	dispose: () => void;
}

/**
 * Turn a bare Escape during a mid-run fold into "cancel this fold" instead of Pi's default
 * "abort the whole run". This is what Pi's own compaction gets for free via
 * `compaction_start`; the fold has no such event, so it installs the listener itself for
 * the duration of the summarization.
 *
 * No sequence disambiguation is needed here. `ProcessTerminal` feeds stdin through
 * `StdinBuffer`, which reassembles an arrow key delivered as `"\x1b"` then `"[A"` before any
 * input listener runs, and holds a lone Escape for a window that is already scaled for SSH
 * and configurable through `PI_TUI_ESC_TIMEOUT` (`terminal.js`, `stdin-buffer.js`). By the
 * time this handler sees `"\x1b"`, Pi has decided it is the Escape key. `consume: true`
 * stops the editor from seeing it. Interactive mode only; a no-op everywhere else.
 */
export function interceptEscape(ctx: ExtensionContext, onCancel: () => void): EscapeInterceptor {
	try {
		if (!ctx.hasUI) return { active: false, dispose: () => {} };
		const ui = ctx.ui as {
			onTerminalInput?: (handler: (data: string) => { consume?: boolean; data?: string } | undefined) => () => void;
		};
		if (typeof ui.onTerminalInput !== "function") return { active: false, dispose: () => {} };
		const unsubscribe = ui.onTerminalInput((data) => {
			if (data === "\x1b" || data === "\u001b") {
				onCancel();
				return { consume: true };
			}
			return undefined;
		});
		return {
			active: true,
			dispose: () => {
				try {
					unsubscribe();
				} catch {
					// A torn-down UI must not break the request.
				}
			},
		};
	} catch {
		return { active: false, dispose: () => {} };
	}
}

/** The streaming working-message label; decoration only, so failures are swallowed. */
export function workingMessageSetter(ctx: ExtensionContext, message: string | undefined): void {
	if (!ctx.hasUI) return;
	try {
		ctx.ui.setWorkingMessage?.(message);
	} catch {
		// Decoration must never affect the request.
	}
}

/**
 * Apply the auth-resolved base URL to a model, exactly as Pi's `_getSummarizationRequestAuth`
 * does. `getApiKeyAndHeaders` returns it separately, and both summarization call sites build
 * their request from the model object, so dropping it silently sends the summary to the
 * default endpoint instead of the configured gateway/region/Azure deployment.
 */
export function withAuthBaseUrl<T extends { baseUrl?: string }>(model: T, baseUrl: string | undefined): T {
	return baseUrl ? { ...model, baseUrl } : model;
}

/**
 * Pi expands `~` in PI_CODING_AGENT_DIR; a literal "~/x" directory would silently split
 * this package's config from the one Pi reads.
 */
export function resolveAgentDir(): string {
	const raw = process.env.PI_CODING_AGENT_DIR;
	if (!raw || raw.trim().length === 0) return join(homedir(), ".pi", "agent");
	const trimmed = raw.trim();
	if (trimmed === "~") return homedir();
	if (trimmed.startsWith("~/")) return resolve(homedir(), trimmed.slice(2));
	return resolve(trimmed);
}

export function asBoolean(value: unknown, fallback: boolean): boolean {
	return typeof value === "boolean" ? value : fallback;
}

export function asCount(value: unknown, fallback: number, min: number, max: number): number {
	if (typeof value !== "number" || !Number.isFinite(value)) return fallback;
	return Math.min(max, Math.max(min, Math.floor(value)));
}

/** Parse a config file without ever throwing: a malformed config must degrade to defaults. */
export function readJsonFile(path: string): { value: unknown; warning?: string } {
	if (!existsSync(path)) return { value: undefined };
	try {
		return { value: JSON.parse(readFileSync(path, "utf8")) };
	} catch (error) {
		return {
			value: undefined,
			warning: `pi-context-handoff: ignoring ${path} (${error instanceof Error ? error.message : "unreadable"}); using defaults.`,
		};
	}
}

export interface OnceNotifier {
	(ctx: ExtensionContext, message: string, variant: "warning" | "info"): void;
	/** Let every message fire again, e.g. at the start of a new session. */
	reset: () => void;
}

/** Emitted at most once per session per distinct message, so a repeating fault cannot spam. */
export function createOnceNotifier(): OnceNotifier {
	const seen = new Set<string>();
	const notify = ((ctx: ExtensionContext, message: string, variant: "warning" | "info") => {
		if (seen.has(message)) return;
		if (!ctx.hasUI) return;
		// Marked only once it could actually be shown, so a headless run does not consume a
		// warning that a later UI-bearing phase should still get.
		seen.add(message);
		try {
			ctx.ui.notify(message, variant);
		} catch {
			// A UI that refuses a notification must not affect the request.
		}
	}) as OnceNotifier;
	notify.reset = () => seen.clear();
	return notify;
}

export function describe(error: unknown): string {
	if (error instanceof Error && typeof error.message === "string") return error.message;
	try {
		return String(error);
	} catch {
		return "unknown error";
	}
}

/**
 * A status-line setter that can never throw. Status is decoration; it must not affect a
 * request or a compaction.
 */
export function statusSetter(ctx: ExtensionContext, key: string): (message: string | undefined) => void {
	return (message) => {
		if (!ctx.hasUI) return;
		try {
			ctx.ui.setStatus(key, message);
		} catch {
			// Status is decoration; never let it affect the request.
		}
	};
}

/**
 * Pi passes its own callbacks to compact()/generateSummary() so the TUI can show a retry
 * indicator. Calling them ourselves means supplying these, or a call that is quietly
 * retrying a failed provider request is indistinguishable from one that has hung.
 */
export function retryCallbacks(ctx: ExtensionContext, key: string, label: string) {
	const say = statusSetter(ctx, key);
	return {
		onRetryScheduled: (attempt: number, maxAttempts: number, delayMs: number) =>
			say(`${label}: retry ${attempt}/${maxAttempts} in ${Math.round(delayMs / 1000)}s`),
		onRetryAttemptStart: () => say(`${label}: retrying`),
		onRetryFinished: () => say(undefined),
	};
}
