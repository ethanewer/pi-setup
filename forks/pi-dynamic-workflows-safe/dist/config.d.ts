/**
 * Configuration constants for pi-dynamic-workflows.
 */
/** Hard ceiling on agents per workflow run; an explicit per-run maxAgents is clamped to it. */
export declare const MAX_AGENTS_PER_RUN = 1000;
/**
 * Agents per run when neither the caller nor `defaultMaxAgents` sets a cap.
 * The 1000 ceiling stays reachable (per-run `maxAgents`, or the
 * `defaultMaxAgents` setting) but is not what an unattended run gets by
 * default — each agent is a subagent session with coding tools and no
 * approval path.
 */
export declare const DEFAULT_MAX_AGENTS_PER_RUN = 100;
/**
 * Default timeout for a single agent in milliseconds. Explicit null (per-run
 * option or `defaultAgentTimeoutMs: null`) still means no hard timeout; the
 * default is finite so a subagent that never settles — and cannot be signalled
 * dead, see runWorkflow's drain — cannot hold a run open indefinitely.
 *
 * Sized for unattended long-running work: a subagent doing real analysis across
 * a large tree can legitimately run far longer than a few minutes, and a
 * timeout here degrades that agent's result to null, so too low a value loses
 * work silently rather than protecting anything.
 */
export declare const DEFAULT_AGENT_TIMEOUT_MS: number;
/**
 * Wall-clock ceiling on one synchronous stretch of workflow-script execution
 * inside the vm realm (vm timeouts only bound synchronous work; an awaiting
 * script yields long before this). Guards against a script that never yields.
 */
export declare const DEFAULT_SCRIPT_TIMEOUT_MS: number;
/**
 * Wall-clock ceiling on the post-script drain of agent() calls the script never
 * awaited. Reached only by an agent that ignores its abort signal (or is stuck
 * in a subagent process that won't die) on a run with no finite agentTimeoutMs;
 * without a bound, such a call keeps the run "running", its lease held, and the
 * manager's promise pending forever. Used when agentTimeoutMs is null; with a
 * finite per-agent timeout the drain waits that long plus a settle grace.
 */
export declare const DEFAULT_DRAIN_TIMEOUT_MS: number;
/** Extra settle time granted on top of a finite agent timeout during the drain. */
export declare const DRAIN_GRACE_MS: number;
/** Maximum concurrent agents (matches Claude Code limit). */
export declare const MAX_CONCURRENCY = 16;
/** Maximum automatic retry attempts after a recoverable agent failure. */
export declare const MAX_AGENT_RETRIES = 3;
/**
 * Automatic retry attempts after a recoverable agent failure when neither the
 * call site nor `defaultAgentRetries` sets one.
 *
 * Non-zero by default because the dominant recoverable failure in practice is a
 * transient provider fault — a 5xx, a dropped connection, an overloaded
 * upstream — which wrapError classifies as recoverable AGENT_EXECUTION_ERROR. At
 * zero, one such blip permanently drops that agent's result to null (or fails
 * the run), which is the single most common way a long unattended run loses
 * work. Genuine quota/rate limits are classified separately and checkpoint the
 * run for auto-resume instead of burning retries against the same wall.
 */
export declare const DEFAULT_AGENT_RETRIES = 2;
/**
 * Base delay before re-attempting a recoverable agent failure. Retries back off
 * as base * 2^(attempt-1); an immediate retry into a transient upstream fault
 * usually just reproduces it.
 */
export declare const AGENT_RETRY_BASE_DELAY_MS = 2000;
/** Ceiling on a single backoff delay, so a long backoff cannot stall a run. */
export declare const AGENT_RETRY_MAX_DELAY_MS = 30000;
/** Default token budget if none specified. */
export declare const DEFAULT_TOKEN_BUDGET: null;
/** Legacy project-relative directory for persisted workflow run state. New writes use workflowProjectPaths(). */
export declare const WORKFLOW_RUNS_DIR = ".pi/workflows/runs";
/** Legacy project-relative directory for saved workflow commands. New writes use workflowProjectPaths(). */
export declare const WORKFLOW_SAVED_DIR = ".pi/workflows/saved";
/** User-level saved workflows directory. */
export declare const USER_WORKFLOW_SAVED_DIR = "~/.pi/workflows/saved";
/** User-level model tiers config file, relative to the home directory. */
export declare const MODEL_TIERS_FILE = ".pi/workflows/model-tiers.json";
/** User-level workflow extension settings file, relative to the home directory. */
export declare const WORKFLOW_SETTINGS_FILE = ".pi/workflows/settings.json";
/** Default keyword that arms workflows mode from interactive input. */
export declare const DEFAULT_KEYWORD_TRIGGER_WORD = "workflow";
/** Normalize a user-configured keyword trigger word. */
export declare function normalizeKeywordTriggerWord(value: unknown): string | undefined;
/**
 * Named workflow subagent definitions directory. Resolved project-relative
 * (cwd/.pi/agents), plus user-level at `~/.pi/agent/agents/` (the primary
 * location, via `getAgentDir()` in agent-registry.ts) with the legacy
 * `~/.pi/agents/` (this constant, home-relative) scanned as a deprecated
 * fallback. Project entries win on name collision, then the primary user
 * location, then the legacy one. Each `*.md` file is an agent definition
 * (frontmatter + body prompt).
 */
export declare const AGENTS_DIR = ".pi/agents";
