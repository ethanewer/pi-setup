import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join, resolve } from "node:path";

/** Which tools the side thread gets. Codex's side thread keeps the parent's tools and
 * relies on instructions to stay non-mutating; "readonly" enforces that structurally
 * instead, because a side thread here has no approval UI in front of it. */
export type BtwToolset = "none" | "readonly" | "full";

export interface BtwModelRef {
	provider: string;
	id: string;
}

export interface BtwConfig {
	enabled: boolean;
	toolset: BtwToolset;
	/** null inherits the main thread's model, which is what Codex does. */
	model: BtwModelRef | null;
	/** null inherits the main thread's thinking level. */
	thinkingLevel: string | null;
	/** Abort a side turn that has run this long. 0 disables the timeout. */
	timeoutMs: number;
	/**
	 * Leave a collapsed card in the main transcript when the side conversation closes.
	 * Off by default, because Codex discards a side conversation on exit. The card is a
	 * custom entry either way, so no model ever sees it.
	 */
	record: boolean;
}

export const THINKING_LEVELS = ["off", "minimal", "low", "medium", "high", "xhigh", "max"] as const;

export const DEFAULT_BTW_CONFIG: BtwConfig = {
	enabled: true,
	toolset: "readonly",
	model: null,
	thinkingLevel: null,
	timeoutMs: 10 * 60 * 1000,
	record: false,
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

export function btwConfigPath(): string {
	return join(resolveAgentDir(), "extensions", "pi-btw-side.json");
}

function asBoolean(value: unknown, fallback: boolean): boolean {
	return typeof value === "boolean" ? value : fallback;
}

function asCount(value: unknown, fallback: number, max: number): number {
	if (typeof value !== "number" || !Number.isFinite(value) || value < 0) return fallback;
	return Math.min(max, Math.floor(value));
}

function asToolset(value: unknown, fallback: BtwToolset): BtwToolset {
	return value === "none" || value === "readonly" || value === "full" ? value : fallback;
}

function asThinkingLevel(value: unknown, fallback: string | null): string | null {
	if (typeof value !== "string") return fallback;
	const trimmed = value.trim();
	return (THINKING_LEVELS as readonly string[]).includes(trimmed) ? trimmed : fallback;
}

/**
 * Accepts "provider/model-id". Model ids may themselves contain slashes
 * (openrouter/anthropic/claude-...), so only the first separator splits.
 */
export function parseModelRef(value: unknown): BtwModelRef | null {
	if (typeof value !== "string") return null;
	const trimmed = value.trim();
	const slash = trimmed.indexOf("/");
	if (slash <= 0 || slash === trimmed.length - 1) return null;
	return { provider: trimmed.slice(0, slash), id: trimmed.slice(slash + 1) };
}

/**
 * Never throws. A malformed config must degrade to "the defaults, with a warning" —
 * never to a broken command or a stuck side mode.
 */
export function loadBtwConfig(): { config: BtwConfig; warning?: string } {
	const path = btwConfigPath();
	if (!existsSync(path)) return { config: DEFAULT_BTW_CONFIG };
	let parsed: unknown;
	try {
		parsed = JSON.parse(readFileSync(path, "utf8"));
	} catch (error) {
		return {
			config: DEFAULT_BTW_CONFIG,
			warning: `btw: ignoring ${path} (${error instanceof Error ? error.message : "unreadable"}); using defaults.`,
		};
	}
	if (typeof parsed !== "object" || parsed === null) return { config: DEFAULT_BTW_CONFIG };
	const raw = parsed as Record<string, unknown>;
	return {
		config: {
			enabled: asBoolean(raw.enabled, DEFAULT_BTW_CONFIG.enabled),
			toolset: asToolset(raw.toolset, DEFAULT_BTW_CONFIG.toolset),
			model: parseModelRef(raw.model),
			thinkingLevel: asThinkingLevel(raw.thinkingLevel, DEFAULT_BTW_CONFIG.thinkingLevel),
			timeoutMs: asCount(raw.timeoutMs, DEFAULT_BTW_CONFIG.timeoutMs, 6 * 60 * 60 * 1000),
			record: asBoolean(raw.record, DEFAULT_BTW_CONFIG.record),
		},
	};
}
