import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join, resolve } from "node:path";

/** Shape Pi passes to compact() as its retry policy (see SettingsManager.getRetrySettings). */
export interface HandoffRetryPolicy {
	enabled: boolean;
	maxRetries: number;
	baseDelayMs: number;
}

export interface HandoffConfig {
	enabled: boolean;
	/** Extra sentences appended to the focus instructions, for project-specific priorities. */
	focus: string;
	retry: HandoffRetryPolicy;
	/** Warn once per session when a handoff brief could not be produced. */
	notifyOnFallback: boolean;
}

export const DEFAULT_HANDOFF_CONFIG: HandoffConfig = {
	enabled: true,
	focus: "",
	// Mirrors Pi's own retry defaults. The whole point of routing through Pi's
	// compact() is that a transient provider fault retries instead of costing the
	// brief, so retries are on unless deliberately disabled.
	retry: { enabled: true, maxRetries: 3, baseDelayMs: 2000 },
	notifyOnFallback: true,
};

/**
 * Pi expands `~` in PI_CODING_AGENT_DIR; a literal "~/x" directory would silently
 * split this package's config from the one Pi reads.
 */
function resolveAgentDir(): string {
	const raw = process.env.PI_CODING_AGENT_DIR;
	if (!raw || raw.trim().length === 0) return join(homedir(), ".pi", "agent");
	const trimmed = raw.trim();
	if (trimmed === "~") return homedir();
	if (trimmed.startsWith("~/")) return resolve(homedir(), trimmed.slice(2));
	return resolve(trimmed);
}

export function handoffConfigPath(): string {
	return join(resolveAgentDir(), "extensions", "pi-context-handoff.json");
}

function asBoolean(value: unknown, fallback: boolean): boolean {
	return typeof value === "boolean" ? value : fallback;
}

function asCount(value: unknown, fallback: number, max: number): number {
	if (typeof value !== "number" || !Number.isFinite(value) || value < 0) return fallback;
	return Math.min(max, Math.floor(value));
}

/**
 * Never throws. A malformed config must not be able to disturb a compaction: the
 * caller is on the turn's critical path, and the worst acceptable outcome here is
 * "no enriched brief", never "the run stopped".
 */
export function loadHandoffConfig(): { config: HandoffConfig; warning?: string } {
	const path = handoffConfigPath();
	if (!existsSync(path)) return { config: DEFAULT_HANDOFF_CONFIG };
	let parsed: unknown;
	try {
		parsed = JSON.parse(readFileSync(path, "utf8"));
	} catch (error) {
		return {
			config: DEFAULT_HANDOFF_CONFIG,
			warning: `pi-context-handoff: ignoring ${path} (${error instanceof Error ? error.message : "unreadable"}); using defaults.`,
		};
	}
	if (typeof parsed !== "object" || parsed === null) return { config: DEFAULT_HANDOFF_CONFIG };
	const raw = parsed as Record<string, unknown>;
	const rawRetry = typeof raw.retry === "object" && raw.retry !== null ? (raw.retry as Record<string, unknown>) : {};
	return {
		config: {
			enabled: asBoolean(raw.enabled, DEFAULT_HANDOFF_CONFIG.enabled),
			focus: typeof raw.focus === "string" ? raw.focus.trim() : DEFAULT_HANDOFF_CONFIG.focus,
			retry: {
				enabled: asBoolean(rawRetry.enabled, DEFAULT_HANDOFF_CONFIG.retry.enabled),
				maxRetries: asCount(rawRetry.maxRetries, DEFAULT_HANDOFF_CONFIG.retry.maxRetries, 10),
				baseDelayMs: asCount(rawRetry.baseDelayMs, DEFAULT_HANDOFF_CONFIG.retry.baseDelayMs, 60_000),
			},
			notifyOnFallback: asBoolean(raw.notifyOnFallback, DEFAULT_HANDOFF_CONFIG.notifyOnFallback),
		},
	};
}
