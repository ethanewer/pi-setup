/**
 * Configuration constants for pi-dynamic-workflows.
 */

/** Hard ceiling on agents per workflow run; an explicit per-run maxAgents is clamped to it. */
export const MAX_AGENTS_PER_RUN = 1000;

/**
 * Agents per run when neither the caller nor `defaultMaxAgents` sets a cap.
 * The 1000 ceiling stays reachable (per-run `maxAgents`, or the
 * `defaultMaxAgents` setting) but is not what an unattended run gets by
 * default — each agent is a subagent session with coding tools and no
 * approval path.
 */
export const DEFAULT_MAX_AGENTS_PER_RUN = 100;

/**
 * Default timeout for a single agent in milliseconds. Explicit null (per-run
 * option or `defaultAgentTimeoutMs: null`) still means no hard timeout; the
 * default is finite so a subagent that never settles — and cannot be signalled
 * dead, see runWorkflow's drain — cannot hold a run open indefinitely.
 */
export const DEFAULT_AGENT_TIMEOUT_MS = 15 * 60 * 1000;

/**
 * Wall-clock ceiling on one synchronous stretch of workflow-script execution
 * inside the vm realm (vm timeouts only bound synchronous work; an awaiting
 * script yields long before this). Guards against a script that never yields.
 */
export const DEFAULT_SCRIPT_TIMEOUT_MS = 60 * 1000;

/**
 * Wall-clock ceiling on the post-script drain of agent() calls the script never
 * awaited. Reached only by an agent that ignores its abort signal (or is stuck
 * in a subagent process that won't die) on a run with no finite agentTimeoutMs;
 * without a bound, such a call keeps the run "running", its lease held, and the
 * manager's promise pending forever. Used when agentTimeoutMs is null; with a
 * finite per-agent timeout the drain waits that long plus a settle grace.
 */
export const DEFAULT_DRAIN_TIMEOUT_MS = 15 * 60 * 1000;

/** Extra settle time granted on top of a finite agent timeout during the drain. */
export const DRAIN_GRACE_MS = 30 * 1000;

/** Maximum concurrent agents (matches Claude Code limit). */
export const MAX_CONCURRENCY = 16;

/** Maximum automatic retry attempts after a recoverable agent failure. */
export const MAX_AGENT_RETRIES = 3;

/** Default token budget if none specified. */
export const DEFAULT_TOKEN_BUDGET = null;

/** Legacy project-relative directory for persisted workflow run state. New writes use workflowProjectPaths(). */
export const WORKFLOW_RUNS_DIR = ".pi/workflows/runs";

/** Legacy project-relative directory for saved workflow commands. New writes use workflowProjectPaths(). */
export const WORKFLOW_SAVED_DIR = ".pi/workflows/saved";

/** User-level saved workflows directory. */
export const USER_WORKFLOW_SAVED_DIR = "~/.pi/workflows/saved";

/** User-level model tiers config file, relative to the home directory. */
export const MODEL_TIERS_FILE = ".pi/workflows/model-tiers.json";

/** User-level workflow extension settings file, relative to the home directory. */
export const WORKFLOW_SETTINGS_FILE = ".pi/workflows/settings.json";

/** Default keyword that arms workflows mode from interactive input. */
export const DEFAULT_KEYWORD_TRIGGER_WORD = "workflow";

/** Normalize a user-configured keyword trigger word. */
export function normalizeKeywordTriggerWord(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const word = value.trim();
  if (!word || word.startsWith("/") || /\s/.test(word)) return undefined;
  return word;
}

/**
 * Named workflow subagent definitions directory. Resolved project-relative
 * (cwd/.pi/agents), plus user-level at `~/.pi/agent/agents/` (the primary
 * location, via `getAgentDir()` in agent-registry.ts) with the legacy
 * `~/.pi/agents/` (this constant, home-relative) scanned as a deprecated
 * fallback. Project entries win on name collision, then the primary user
 * location, then the legacy one. Each `*.md` file is an agent definition
 * (frontmatter + body prompt).
 */
export const AGENTS_DIR = ".pi/agents";
