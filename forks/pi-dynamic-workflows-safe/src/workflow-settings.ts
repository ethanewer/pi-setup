/**
 * User-level settings for pi-dynamic-workflows.
 *
 * Stored separately from Pi's own settings.json so extension preferences remain
 * stable without depending on host-internal config shape.
 */

import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { MAX_AGENT_RETRIES, MAX_AGENTS_PER_RUN, MAX_CONCURRENCY, normalizeKeywordTriggerWord } from "./config.js";
import { workflowHomeDir, workflowProjectPaths } from "./workflow-paths.js";

export interface WorkflowSettings {
  keywordTriggerEnabled?: boolean;
  /** Literal keyword that arms workflows mode from interactive input. */
  keywordTriggerWord?: string;
  defaultAgentTimeoutMs?: number | null;
  /**
   * Default hard token budget applied to runs that don't pass their own
   * `tokenBudget` (#68). null explicitly means "no budget" (useful in a
   * project override to cancel a global budget); omitted also means no budget.
   */
  defaultTokenBudget?: number | null;
  /** Default max concurrent agents per run. Clamped to the runtime maximum. */
  defaultConcurrency?: number;
  /**
   * Default cap on total agents per run when the caller passes no `maxAgents`
   * (default DEFAULT_MAX_AGENTS_PER_RUN). Clamped to MAX_AGENTS_PER_RUN, so the
   * 1000 ceiling stays reachable for anyone who wants it.
   */
  defaultMaxAgents?: number;
  /** Default retry attempts after recoverable agent failures. */
  defaultAgentRetries?: number;
  /** Bottom task-panel display mode: "compact" (default, one line per run) | "detailed". */
  progressPanelMode?: "compact" | "detailed";
  /** Max agents shown per phase in detailed progress mode (default 8). */
  progressPanelMaxAgents?: number;
  /**
   * Persist each workflow subagent transcript as a real pi session file under
   * the standard sessions directory (~/.pi/agent/sessions/<encoded-cwd>/),
   * keyed by the project cwd. Default false: subagent sessions stay in-memory
   * and only the compacted history embedded in the run JSON survives.
   */
  persistAgentSessions?: boolean;
  /**
   * Character cap on a delivered background-run result's JSON-dump fallback
   * before truncation (default 400). String results and `verdict`/`report`/
   * `summary`/`synthesis` fields are never truncated.
   */
  deliveredResultMaxChars?: number;
  /**
   * Extra tool names to deny in workflow subagent sessions, on top of the
   * always-on `workflow`/`workflow_control` defaults (#107). Use it to block
   * other recursive-orchestration tools you have installed (e.g. a pi-subagents
   * tool) so a subagent can't fan out through them.
   */
  excludeSubagentTools?: string[];
  /**
   * Trust workflow files stored inside the project directory itself
   * (`<cwd>/.pi/workflows/saved`, the pre-3.x location). Whatever repository is
   * checked out can supply those, and a saved workflow becomes a `/<name>`
   * command whose script runs subagents with tools — so by default they are
   * confirmed at invocation instead of resolved silently, and are not resolved
   * at all where no one can be asked (a `workflow` tool `name`, a nested
   * `workflow('name')`). Set true to restore unprompted resolution. Put it in
   * the project override (`~/.pi/workflows/projects/<key>/settings.json`) to
   * trust one project only.
   */
  trustProjectLocalWorkflows?: boolean;
  /**
   * Hosts the web tools may fetch even though they resolve to a local or
   * private-network address, e.g. `["localhost:3000", "dev.internal"]`. Matched
   * case-insensitively against the URL's host and port; an entry with no port
   * matches only the scheme's default port (see WebFetchPolicy.allowedHosts).
   */
  webFetchAllowedHosts?: string[];
  /**
   * Allow the web tools to fetch ANY loopback/link-local/private-range target
   * (default false). `webFetchAllowedHosts` is the narrower knob; this one is
   * for a machine where reaching the local network is the point.
   */
  webFetchAllowPrivateNetwork?: boolean;
  /**
   * What an agent that asked for `isolation: "worktree"` should do when the
   * worktree cannot be created: "error" (the default when `git worktree add`
   * fails) fails that agent — recoverably, so only that agent is lost, not the
   * run — instead of running it in the shared working tree; "shared-tree"
   * restores the pre-3.4 logged fallback. A cwd that is not a git repository at
   * all defaults to "shared-tree" with a warning, since isolation was never
   * available there; set "error" here to fail those agents too.
   */
  worktreeIsolationFallback?: "error" | "shared-tree";
}

export interface WorkflowSettingsStore {
  load(): WorkflowSettings;
  save(settings: WorkflowSettings): void;
}

export interface WorkflowSettingsOptions {
  /** Explicit settings path, primarily for tests and migrations. */
  settingsPath?: string;
  /** Project cwd whose project-level settings should override global settings. */
  cwd?: string;
  /** Explicit project settings path, primarily for tests. */
  projectSettingsPath?: string;
  /** Save destination when using saveWorkflowSettings with cwd. Default: global. */
  scope?: "global" | "project";
}

/** Path to the user-level workflow settings JSON file (~/.pi/workflows/settings.json). */
export function getWorkflowSettingsPath(): string {
  return join(workflowHomeDir(), "settings.json");
}

/** Path to this project's optional workflow settings override. */
export function getWorkflowProjectSettingsPath(cwd: string): string {
  return workflowProjectPaths(cwd).settingsPath;
}

/** Load settings from disk. Missing, corrupt, or invalid files resolve to {}. */
export function loadWorkflowSettings(settingsPathOrOptions?: string | WorkflowSettingsOptions): WorkflowSettings {
  const options = normalizeOptions(settingsPathOrOptions);
  const globalSettings = readSettings(options.settingsPath ?? getWorkflowSettingsPath());
  const projectPath =
    options.projectSettingsPath ?? (options.cwd ? getWorkflowProjectSettingsPath(options.cwd) : undefined);
  if (!projectPath) return globalSettings;
  return { ...globalSettings, ...readSettings(projectPath) };
}

/** Merge known settings into the user-level settings file. */
export function saveWorkflowSettings(
  settings: WorkflowSettings,
  settingsPathOrOptions?: string | WorkflowSettingsOptions,
): void {
  const options = normalizeOptions(settingsPathOrOptions);
  const projectPath =
    options.projectSettingsPath ?? (options.cwd ? getWorkflowProjectSettingsPath(options.cwd) : undefined);
  const path =
    options.scope === "project" && projectPath ? projectPath : (options.settingsPath ?? getWorkflowSettingsPath());
  const dir = dirname(path);
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });

  const existing = readObject(path);
  writeFileSync(path, `${JSON.stringify({ ...existing, ...normalizeSettings(settings) }, null, 2)}\n`, "utf-8");
}

/** Save a global preference and update an existing project override if one is present. */
export function saveWorkflowSettingsForCwd(settings: WorkflowSettings, cwd: string): void {
  saveWorkflowSettings(settings);
  const projectPath = getWorkflowProjectSettingsPath(cwd);
  if (existsSync(projectPath)) {
    saveWorkflowSettings(settings, { projectSettingsPath: projectPath, scope: "project" });
  }
}

function normalizeOptions(settingsPathOrOptions?: string | WorkflowSettingsOptions): WorkflowSettingsOptions {
  return typeof settingsPathOrOptions === "string"
    ? { settingsPath: settingsPathOrOptions }
    : (settingsPathOrOptions ?? {});
}

function readSettings(path: string): WorkflowSettings {
  if (!existsSync(path)) return {};
  try {
    return normalizeSettings(JSON.parse(readFileSync(path, "utf-8")));
  } catch {
    return {};
  }
}

function normalizeSettings(value: unknown): WorkflowSettings {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  const raw = value as Record<string, unknown>;
  const settings: WorkflowSettings = {};
  if (typeof raw.keywordTriggerEnabled === "boolean") {
    settings.keywordTriggerEnabled = raw.keywordTriggerEnabled;
  }
  const keywordTriggerWord = normalizeKeywordTriggerWord(raw.keywordTriggerWord);
  if (keywordTriggerWord !== undefined) settings.keywordTriggerWord = keywordTriggerWord;
  if (raw.defaultAgentTimeoutMs === null) {
    settings.defaultAgentTimeoutMs = null;
  } else if (
    typeof raw.defaultAgentTimeoutMs === "number" &&
    Number.isFinite(raw.defaultAgentTimeoutMs) &&
    raw.defaultAgentTimeoutMs > 0
  ) {
    settings.defaultAgentTimeoutMs = raw.defaultAgentTimeoutMs;
  }
  if (raw.defaultTokenBudget === null) {
    settings.defaultTokenBudget = null;
  } else {
    const defaultTokenBudget = normalizeInteger(raw.defaultTokenBudget, 1, Number.MAX_SAFE_INTEGER);
    if (defaultTokenBudget !== undefined) settings.defaultTokenBudget = defaultTokenBudget;
  }
  const defaultConcurrency = normalizeInteger(raw.defaultConcurrency, 1, MAX_CONCURRENCY);
  if (defaultConcurrency !== undefined) settings.defaultConcurrency = defaultConcurrency;
  const defaultMaxAgents = normalizeInteger(raw.defaultMaxAgents, 1, MAX_AGENTS_PER_RUN);
  if (defaultMaxAgents !== undefined) settings.defaultMaxAgents = defaultMaxAgents;
  const defaultAgentRetries = normalizeInteger(raw.defaultAgentRetries, 0, MAX_AGENT_RETRIES);
  if (defaultAgentRetries !== undefined) settings.defaultAgentRetries = defaultAgentRetries;
  if (raw.progressPanelMode === "compact" || raw.progressPanelMode === "detailed") {
    settings.progressPanelMode = raw.progressPanelMode;
  }
  if (
    typeof raw.progressPanelMaxAgents === "number" &&
    Number.isFinite(raw.progressPanelMaxAgents) &&
    raw.progressPanelMaxAgents >= 1
  ) {
    settings.progressPanelMaxAgents = Math.min(1000, Math.floor(raw.progressPanelMaxAgents));
  }
  if (typeof raw.persistAgentSessions === "boolean") {
    settings.persistAgentSessions = raw.persistAgentSessions;
  }
  if (typeof raw.trustProjectLocalWorkflows === "boolean") {
    settings.trustProjectLocalWorkflows = raw.trustProjectLocalWorkflows;
  }
  if (typeof raw.webFetchAllowPrivateNetwork === "boolean") {
    settings.webFetchAllowPrivateNetwork = raw.webFetchAllowPrivateNetwork;
  }
  if (Array.isArray(raw.webFetchAllowedHosts)) {
    const hosts = raw.webFetchAllowedHosts.filter((h): h is string => typeof h === "string" && h.trim().length > 0);
    if (hosts.length) settings.webFetchAllowedHosts = hosts;
  }
  if (raw.worktreeIsolationFallback === "error" || raw.worktreeIsolationFallback === "shared-tree") {
    settings.worktreeIsolationFallback = raw.worktreeIsolationFallback;
  }
  const deliveredResultMaxChars = normalizeInteger(raw.deliveredResultMaxChars, 1, 1_000_000);
  if (deliveredResultMaxChars !== undefined) settings.deliveredResultMaxChars = deliveredResultMaxChars;
  if (Array.isArray(raw.excludeSubagentTools)) {
    const names = raw.excludeSubagentTools.filter((t): t is string => typeof t === "string" && t.trim().length > 0);
    if (names.length) settings.excludeSubagentTools = names;
  }
  return settings;
}

function normalizeInteger(value: unknown, min: number, max: number): number | undefined {
  if (typeof value !== "number" || !Number.isFinite(value) || value < min) return undefined;
  return Math.min(max, Math.floor(value));
}

function readObject(path: string): Record<string, unknown> {
  if (!existsSync(path)) return {};
  try {
    const parsed = JSON.parse(readFileSync(path, "utf-8"));
    return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? (parsed as Record<string, unknown>) : {};
  } catch {
    return {};
  }
}
