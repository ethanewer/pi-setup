/**
 * User-level settings for pi-dynamic-workflows.
 *
 * Stored separately from Pi's own settings.json so extension preferences remain
 * stable without depending on host-internal config shape.
 */
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
export declare function getWorkflowSettingsPath(): string;
/** Path to this project's optional workflow settings override. */
export declare function getWorkflowProjectSettingsPath(cwd: string): string;
/** Load settings from disk. Missing, corrupt, or invalid files resolve to {}. */
export declare function loadWorkflowSettings(settingsPathOrOptions?: string | WorkflowSettingsOptions): WorkflowSettings;
/** Merge known settings into the user-level settings file. */
export declare function saveWorkflowSettings(settings: WorkflowSettings, settingsPathOrOptions?: string | WorkflowSettingsOptions): void;
/** Save a global preference and update an existing project override if one is present. */
export declare function saveWorkflowSettingsForCwd(settings: WorkflowSettings, cwd: string): void;
