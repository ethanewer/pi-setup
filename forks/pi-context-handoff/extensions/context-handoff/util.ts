/**
 * Helpers shared by the handoff and fold halves of this package. These existed in both
 * predecessor packages (pi-context-handoff and pi-codex-compaction) as near-identical
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

/** Emitted at most once per session per distinct message, so a repeating fault cannot spam. */
export function createOnceNotifier() {
	const seen = new Set<string>();
	return (ctx: ExtensionContext, message: string, variant: "warning" | "info") => {
		if (seen.has(message)) return;
		seen.add(message);
		if (!ctx.hasUI) return;
		try {
			ctx.ui.notify(message, variant);
		} catch {
			// A UI that refuses a notification must not affect the request.
		}
	};
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
