/**
 * Unified configuration for pi-context-handoff's three halves:
 *
 *   - `handoff`: shaping Pi's native between-runs compaction into a handoff brief.
 *     Reads the top-level keys of pi-context-handoff.json, exactly as the standalone
 *     pi-context-handoff package always has.
 *   - `fold`: the mid-run Codex-style fold. Reads the optional `fold` object in
 *     pi-context-handoff.json only.
 *   - `resume`: restarting a run Pi abandoned. Reads the optional `resume` key; defaults to
 *     the top-level `enabled`, so the package-wide switch turns it off too.
 *
 * Never throws. All three are on critical paths (before every LLM call; during a
 * compaction; when a run is about to end), so a malformed config must degrade to defaults
 * rather than disturb a request or a compaction.
 */

import { join } from "node:path";

import { DEFAULT_FOLD_SETTINGS, type FoldSettings } from "./fold.js";
import {
	asBoolean,
	asCount,
	DEFAULT_SUMMARIZE_TIMEOUT_MS,
	type RetryPolicy,
	readJsonFile,
	resolveAgentDir,
} from "./util.js";

export interface HandoffConfig {
	enabled: boolean;
	/** Extra sentences appended to the focus instructions, for project-specific priorities. */
	focus: string;
	retry: RetryPolicy;
	/** Warn once per session when a handoff brief could not be produced. */
	notifyOnFallback: boolean;
	/**
	 * Upper bound on the handoff summarization call, retries included. Pi's global undici idle
	 * timeout only covers inactivity, so a slow-but-flowing stream or the retry schedule can
	 * outlast it; this caps the whole call. 0 disables the bound. See `summarizeTimeoutMs` in
	 * `FoldConfig` for the fold half.
	 */
	summarizeTimeoutMs: number;
}

/**
 * The resume half restarts runs Pi abandoned, so it is the most intrusive thing this
 * package does. It gets its own switch because it is the behaviour a user is most likely to
 * want off while keeping briefs and folding. It defaults to the handoff's own `enabled`, so
 * the package-wide kill switch still turns it off.
 */
export interface ResumeConfig {
	enabled: boolean;
}

export interface FoldConfig extends FoldSettings {
	enabled: boolean;
	/** Extra sentences appended to the summarization focus, for project-specific priorities. */
	focus: string;
	retry: RetryPolicy;
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
	/**
	 * Upper bound on one fold summarization call, retries included. Pi's global undici idle
	 * timeout covers inactivity, not total duration, so a slow-but-flowing stream or the retry
	 * schedule can outlast it; this caps the whole call. 0 disables the bound.
	 */
	summarizeTimeoutMs: number;
}

export interface ExtensionConfig {
	handoff: HandoffConfig;
	fold: FoldConfig;
	resume: ResumeConfig;
}

const DEFAULT_RETRY: RetryPolicy = { enabled: true, maxRetries: 3, baseDelayMs: 2000 };

export const DEFAULT_HANDOFF_CONFIG: HandoffConfig = {
	enabled: true,
	focus: "",
	// Mirrors Pi's own retry defaults. The whole point of routing through Pi's
	// compact() is that a transient provider fault retries instead of costing the
	// brief, so retries are on unless deliberately disabled.
	retry: { ...DEFAULT_RETRY },
	notifyOnFallback: true,
	summarizeTimeoutMs: DEFAULT_SUMMARIZE_TIMEOUT_MS,
};

export const DEFAULT_RESUME_CONFIG: ResumeConfig = { enabled: true };

export const DEFAULT_FOLD_CONFIG: FoldConfig = {
	...DEFAULT_FOLD_SETTINGS,
	enabled: true,
	focus: "",
	// Mirrors Pi's own retry defaults: a transient provider fault should cost a retry, not
	// the fold.
	retry: { ...DEFAULT_RETRY },
	summaryReserveTokens: 16_384,
	maxFailures: 3,
	maxFoldsWithoutProgress: 2,
	maxTrimAttempts: 5,
	notify: true,
	// Baseline only: `loadExtensionConfig` normally overrides this with the handoff's value so
	// the fold inherits a top-level `summarizeTimeoutMs`. It stays here because `FoldConfig`
	// requires the field for callers that build a config directly.
	summarizeTimeoutMs: DEFAULT_SUMMARIZE_TIMEOUT_MS,
};

export function handoffConfigPath(): string {
	return join(resolveAgentDir(), "extensions", "pi-context-handoff.json");
}



function parseRetry(raw: unknown, fallback: RetryPolicy): RetryPolicy {
	const r = typeof raw === "object" && raw !== null ? (raw as Record<string, unknown>) : {};
	return {
		enabled: asBoolean(r.enabled, fallback.enabled),
		maxRetries: asCount(r.maxRetries, fallback.maxRetries, 0, 10),
		baseDelayMs: asCount(r.baseDelayMs, fallback.baseDelayMs, 0, 60_000),
	};
}

function parseHandoff(raw: Record<string, unknown>): HandoffConfig {
	const d = DEFAULT_HANDOFF_CONFIG;
	return {
		enabled: asBoolean(raw.enabled, d.enabled),
		focus: typeof raw.focus === "string" ? raw.focus.trim() : d.focus,
		retry: parseRetry(raw.retry, d.retry),
		notifyOnFallback: asBoolean(raw.notifyOnFallback, d.notifyOnFallback),
		summarizeTimeoutMs: asCount(raw.summarizeTimeoutMs, d.summarizeTimeoutMs, 0, 3_600_000),
	};
}

function parseResume(raw: unknown, fallbackEnabled: boolean): ResumeConfig {
	if (raw === false) return { enabled: false };
	if (typeof raw === "object" && raw !== null) {
		return { enabled: asBoolean((raw as Record<string, unknown>).enabled, fallbackEnabled) };
	}
	return { enabled: asBoolean(raw, fallbackEnabled) };
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

function parseFold(
	raw: Record<string, unknown>,
	fallbackEnabled: boolean,
	fallbackTimeoutMs: number,
): FoldConfig {
	const d = DEFAULT_FOLD_CONFIG;
	return {
		// The fallback chains top-level enabled, so a pre-merge {"enabled": false}
		// config still turns the whole package off; fold.enabled can re-enable it.
		enabled: asBoolean(raw.enabled, fallbackEnabled),
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
		summarizeTimeoutMs: asCount(raw.summarizeTimeoutMs, fallbackTimeoutMs, 0, 3_600_000),
		retry: parseRetry(raw.retry, d.retry),
	};
}

/**
 * Load the merged configuration. Handoff keys come from the top level of
 * pi-context-handoff.json (unchanged from the standalone package). Fold settings come from
 * its optional `fold` object; any other value means defaults. Warnings are collected
 * rather than emitted so each caller can surface them through its own once-per-session
 * notifier.
 */
export function loadExtensionConfig(): { config: ExtensionConfig; warnings: string[] } {
	const warnings: string[] = [];
	const main = readJsonFile(handoffConfigPath());
	if (main.warning) warnings.push(main.warning);
	const mainRaw =
		typeof main.value === "object" && main.value !== null ? (main.value as Record<string, unknown>) : {};

	const handoff = parseHandoff(mainRaw);

	let fold: FoldConfig;
	if (mainRaw.fold === false) {
		// Explicit kill switch for just the mid-run half.
		fold = {
			...DEFAULT_FOLD_CONFIG,
			enabled: false,
			summarizeTimeoutMs: handoff.summarizeTimeoutMs,
			retry: { ...DEFAULT_FOLD_CONFIG.retry },
		};
	} else if (typeof mainRaw.fold === "object" && mainRaw.fold !== null) {
		fold = parseFold(mainRaw.fold as Record<string, unknown>, handoff.enabled, handoff.summarizeTimeoutMs);
	} else {
		fold = {
			...DEFAULT_FOLD_CONFIG,
			enabled: handoff.enabled,
			summarizeTimeoutMs: handoff.summarizeTimeoutMs,
			retry: { ...DEFAULT_FOLD_CONFIG.retry },
		};
	}

	// Top-level enabled is the package-wide switch, so resume follows it unless it is set
	// explicitly (`resume: false` or `resume: { enabled: ... }`).
	const resume = parseResume(mainRaw.resume, handoff.enabled);

	return { config: { handoff, fold, resume }, warnings };
}
