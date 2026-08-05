import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join, resolve } from "node:path";

import { DEFAULT_FOLD_SETTINGS, type FoldSettings } from "./fold.js";

/** Shape Pi passes to its summarization calls as a retry policy. */
export interface CodexRetryPolicy {
	enabled: boolean;
	maxRetries: number;
	baseDelayMs: number;
}

export interface CodexCompactionConfig extends FoldSettings {
	enabled: boolean;
	/** Extra sentences appended to the summarization focus, for project-specific priorities. */
	focus: string;
	retry: CodexRetryPolicy;
	/** Cap on the summary itself; `generateSummary` uses 80% of this as its max output. */
	summaryReserveTokens: number;
	/** Consecutive summarization failures after which the fold is abandoned for the session. */
	maxFailures: number;
	/**
	 * Folds allowed without the request dropping under the trigger. Folding that is not
	 * achieving its purpose only costs context, so it stops rather than continuing. Codex needs
	 * no equivalent: its compaction reduces to roughly 20k, far below any trigger.
	 */
	maxFoldsWithoutProgress: number;
	/**
	 * Codex-style retries that shrink the prefix when summarizing it overflows. Codex removes one
	 * item at a time and keeps going until a single item is left; this drops 25% per attempt, so
	 * the default of 5 reaches roughly a quarter of the original for a fifth of the round trips.
	 */
	maxTrimAttempts: number;
	/** Announce each fold. On by default: a run silently sending a quarter of its history is worse. */
	notify: boolean;
}

export const DEFAULT_CODEX_COMPACTION_CONFIG: CodexCompactionConfig = {
	...DEFAULT_FOLD_SETTINGS,
	enabled: true,
	focus: "",
	// Mirrors Pi's own retry defaults: a transient provider fault should cost a retry, not
	// the fold.
	retry: { enabled: true, maxRetries: 3, baseDelayMs: 2000 },
	summaryReserveTokens: 16_384,
	maxFailures: 3,
	maxFoldsWithoutProgress: 2,
	maxTrimAttempts: 5,
	notify: true,
};

/**
 * Pi expands `~` in PI_CODING_AGENT_DIR; a literal "~/x" directory would silently split
 * this package's config from the one Pi reads.
 */
function resolveAgentDir(): string {
	const raw = process.env.PI_CODING_AGENT_DIR;
	if (!raw || raw.trim().length === 0) return join(homedir(), ".pi", "agent");
	const trimmed = raw.trim();
	if (trimmed === "~") return homedir();
	if (trimmed.startsWith("~/")) return resolve(homedir(), trimmed.slice(2));
	return resolve(trimmed);
}

export function codexCompactionConfigPath(): string {
	return join(resolveAgentDir(), "extensions", "pi-codex-compaction.json");
}

function asBoolean(value: unknown, fallback: boolean): boolean {
	return typeof value === "boolean" ? value : fallback;
}

function asCount(value: unknown, fallback: number, min: number, max: number): number {
	if (typeof value !== "number" || !Number.isFinite(value)) return fallback;
	return Math.min(max, Math.max(min, Math.floor(value)));
}

/**
 * Trigger fraction, clamped the way Codex clamps it.
 *
 * Codex takes `min(config_limit, context_window * 9 / 10)` — a configured limit can only
 * ever make it compact *earlier*, never later, because compacting later than 90% is the one
 * setting that cannot be recovered from. The same asymmetry applies here, so 0.9 is the
 * ceiling and not merely the default.
 */
function asTriggerPercent(value: unknown, fallback: number): number {
	if (typeof value !== "number" || !Number.isFinite(value)) return fallback;
	if (value <= 0) return fallback;
	return Math.min(value, DEFAULT_FOLD_SETTINGS.triggerPercent);
}

/**
 * Never throws. This runs before every LLM call, so a malformed config must degrade to
 * defaults rather than disturb a request.
 */
export function loadCodexCompactionConfig(): { config: CodexCompactionConfig; warning?: string } {
	const path = codexCompactionConfigPath();
	if (!existsSync(path)) return { config: DEFAULT_CODEX_COMPACTION_CONFIG };
	let parsed: unknown;
	try {
		parsed = JSON.parse(readFileSync(path, "utf8"));
	} catch (error) {
		return {
			config: DEFAULT_CODEX_COMPACTION_CONFIG,
			warning: `pi-codex-compaction: ignoring ${path} (${error instanceof Error ? error.message : "unreadable"}); using defaults.`,
		};
	}
	if (typeof parsed !== "object" || parsed === null) return { config: DEFAULT_CODEX_COMPACTION_CONFIG };
	const raw = parsed as Record<string, unknown>;
	const rawRetry = typeof raw.retry === "object" && raw.retry !== null ? (raw.retry as Record<string, unknown>) : {};
	const d = DEFAULT_CODEX_COMPACTION_CONFIG;
	return {
		config: {
			enabled: asBoolean(raw.enabled, d.enabled),
			focus: typeof raw.focus === "string" ? raw.focus.trim() : d.focus,
			triggerPercent: asTriggerPercent(raw.triggerPercent, d.triggerPercent),
			keepRecentTokens: asCount(raw.keepRecentTokens, d.keepRecentTokens, 2_000, 200_000),
			pinUserTokens: asCount(raw.pinUserTokens, d.pinUserTokens, 0, 100_000),
			minSavingTokens: asCount(raw.minSavingTokens, d.minSavingTokens, 0, 100_000),
			toolOverheadTokens: asCount(raw.toolOverheadTokens, d.toolOverheadTokens, 0, 100_000),
			summaryReserveTokens: asCount(raw.summaryReserveTokens, d.summaryReserveTokens, 2_048, 200_000),
			maxFailures: asCount(raw.maxFailures, d.maxFailures, 1, 20),
			maxFoldsWithoutProgress: asCount(raw.maxFoldsWithoutProgress, d.maxFoldsWithoutProgress, 1, 20),
			maxTrimAttempts: asCount(raw.maxTrimAttempts, d.maxTrimAttempts, 0, 10),
			notify: asBoolean(raw.notify, d.notify),
			retry: {
				enabled: asBoolean(rawRetry.enabled, d.retry.enabled),
				maxRetries: asCount(rawRetry.maxRetries, d.retry.maxRetries, 0, 10),
				baseDelayMs: asCount(rawRetry.baseDelayMs, d.retry.baseDelayMs, 0, 60_000),
			},
		},
	};
}
