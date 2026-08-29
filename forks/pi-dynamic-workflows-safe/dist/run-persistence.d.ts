/**
 * Workflow run state persistence for pause/resume support.
 */
import type { AgentUsage } from "./agent.js";
import type { AgentHistoryEntry } from "./agent-history.js";
import type { WorkflowErrorCode } from "./errors.js";
import { type PersistenceFsLayer } from "./fs-persistence.js";
export type RunStatus = "pending" | "running" | "paused" | "completed" | "failed" | "aborted";
export interface PersistedAgentState {
    id: number;
    /** Runtime call identity (`${runId}:${callIndex}`), used to rehydrate journaled results. */
    callId?: string;
    label: string;
    phase?: string;
    prompt: string;
    status: "queued" | "running" | "done" | "error" | "skipped";
    result?: unknown;
    /** Compact result written by releases before full agent results were retained. */
    resultPreview?: string;
    error?: string;
    errorCode?: WorkflowErrorCode;
    recoverable?: boolean;
    history?: AgentHistoryEntry[];
    startedAt?: string;
    endedAt?: string;
    /** Tokens used by this agent (a scalar estimate when the provider reports no usage). */
    tokens?: number;
    /** Per-agent token usage breakdown, when the provider reported one. */
    tokenUsage?: AgentUsage;
    /** The model this agent ran on (provider/id), when known. */
    model?: string;
}
/** Serialized journal entry; runId is absent on legacy numeric-only journals. */
export interface PersistedJournalEntry {
    index: number;
    runId?: string;
    hash: string;
    result: unknown;
    storeDelta?: Record<string, unknown>;
    /** The model the call ran on; absent on journals written before this field existed. */
    model?: string;
}
export interface PersistedRunState {
    runId: string;
    workflowName: string;
    script: string;
    args?: unknown;
    /** The pi session this run belongs to. Runs persist on disk across sessions but
     * the navigator shows only the current session's runs (undefined = legacy/global). */
    sessionId?: string;
    status: RunStatus;
    /** Why a paused run is paused (e.g. "usage_limit" when a provider quota was hit). */
    pauseReason?: string;
    /** Provider reset hint for a usage-limit pause, e.g. "Resets in ~3h" (verbatim). */
    resetHint?: string;
    phases: string[];
    currentPhase?: string;
    agents: PersistedAgentState[];
    logs: string[];
    result?: unknown;
    startedAt: string;
    updatedAt: string;
    completedAt?: string;
    durationMs?: number;
    tokenUsage?: {
        input: number;
        output: number;
        total: number;
        cost?: number;
        cacheRead?: number;
        cacheWrite?: number;
    };
    /**
     * Cached agent/checkpoint results for resume, keyed by deterministic call
     * index. `runId` namespaces `index` (a nested workflow() call restarts its
     * own callSeq at 0) — absent on journals persisted before that namespacing
     * existed; see PersistedJournalEntry.runId in workflow.ts / the manager's
     * resume() for the resume-time legacy-degradation behavior. `storeDelta` is
     * this call's SharedStore write delta, replayed additively on resume.
     */
    journal?: PersistedJournalEntry[];
    /**
     * Opt-out of auto-resume for this run (default true, i.e. eligible unless
     * explicitly set to false via ExecOptions.autoResume). Set once at run start
     * and carried through resumes; see UsageLimitScheduler.
     */
    autoResume?: boolean;
    /**
     * The run's resolved hard token budget, fixed at start (per-run value, else
     * the manager default at the time). Resume re-applies THIS value — never the
     * current default — so an explicit no-budget (`null`) or custom cap survives
     * a pause/resume cycle. Absent on legacy runs (resumed unbudgeted).
     */
    tokenBudget?: number | null;
    /**
     * Named toolset tag (WorkflowManagerOptions.toolsets). ToolDefinitions are
     * functions and can't be serialized, so this tag is how a resumed run (e.g.
     * /deep-research with web tools) re-resolves the tool set it started with.
     */
    toolset?: string;
    /**
     * The run's resolved cap on total agents, fixed at start (per-run value,
     * else undefined so runWorkflow applies its own DEFAULT_MAX_AGENTS_PER_RUN).
     * Resume re-applies THIS value — never the manager's current default — same
     * rationale as tokenBudget. Absent on legacy runs (resumed with no cap
     * carried forward, i.e. runWorkflow's own default applies).
     */
    maxAgents?: number;
    /**
     * The run's resolved per-agent timeout, fixed at start (per-run value, else
     * the manager default at the time). Absent on legacy runs — unlike
     * tokenBudget, a legacy run's real timeout was never "no timeout" by
     * omission; it was always the manager's default (pre-A1 resume always fell
     * back to it), so resume applies the manager's CURRENT default for such
     * runs rather than null, preserving both the run's original semantics and
     * pre-fix resume behavior.
     */
    agentTimeoutMs?: number | null;
    /**
     * The run's resolved concurrency, fixed at start (per-run value, else the
     * manager's concurrency at the time). Same rationale as tokenBudget.
     */
    concurrency?: number;
    /**
     * The run's resolved agent-retry count, fixed at start (per-run value, else
     * the manager default at the time). Same rationale as tokenBudget.
     */
    agentRetries?: number;
    /**
     * Auto-resume attempt counter for the current usage_limit pause-cycle, owned
     * and persisted by UsageLimitScheduler (best-effort). Absent/0 means no
     * auto-resume attempt has been recorded yet.
     */
    autoResumeAttempts?: number;
    /**
     * The install that wrote this record (workflowInstallId()). Absent on records
     * written before provenance existed and on records this install never wrote —
     * a run store that arrived with a cloned repository, say. Only a record whose
     * provenance matches this install is ever resumed without a human saying so.
     */
    installId?: string;
    /**
     * Absolute path this record was read from, and which store that path belongs
     * to. Both are assigned by the reader on every load()/list(); they are never
     * read from the file (a file claiming "global" while sitting in a project
     * directory must not be believed) and never written to it.
     */
    sourcePath?: string;
    sourceStore?: "global" | "legacy";
    /**
     * Set when a record first read from a project-local run store is written into
     * the global store (status reconciliation, stop, attempt counters): the
     * script still came from the project directory, so it stays gated on explicit
     * confirmation regardless of where the file now lives.
     */
    foreignSource?: string;
    /**
     * Undelivered background-result payload waiting for the originating session's
     * delivery endpoint. Written before the send attempt (fail-closed); cleared
     * only after a successful session-routed delivery.
     */
    pendingDelivery?: PendingDeliveryMarker;
}
/**
 * Disk/memory marker for a background result that still needs conversation
 * delivery. Kept small on purpose — never store full agent transcripts here.
 */
export type PendingDeliveryMarker = {
    kind: "complete";
} | {
    kind: "text";
    text: string;
};
export interface RunPersistence {
    /**
     * Save current run state. `updatedAt` is restamped to now, since every write
     * normally reports progress — except with `preserveUpdatedAt`, for a write
     * that changes bookkeeping only (stamping provenance on a pre-existing
     * record) and must not move the run in the recency ordering the listing and
     * the retention cap both use.
     */
    save(state: PersistedRunState, options?: {
        preserveUpdatedAt?: boolean;
    }): void;
    /** Load a persisted run by ID. */
    load(runId: string): PersistedRunState | null;
    /** List all persisted runs. */
    list(): PersistedRunState[];
    /** Delete a persisted run. */
    delete(runId: string): boolean;
    /**
     * Acquire an exclusive cross-process lease for a run. Returns null when another
     * live process owns the run; stale/corrupt lock files are removed and retried.
     */
    acquireRunLease(runId: string): RunLease | null;
    /** Release a lease previously returned by acquireRunLease(). */
    releaseRunLease(lease: RunLease): void;
    /** Get runs directory path. */
    getRunsDir(): string;
}
export interface RunLease {
    runId: string;
    token: string;
}
/**
 * Filesystem operations used by run persistence.
 * Exposed for testing – pass overrides to inject mock implementations.
 * (Alias of the shared PersistenceFsLayer — see fs-persistence.ts.)
 */
export type FsLayer = PersistenceFsLayer;
/**
 * Retention policy for terminal (completed/failed/aborted) runs kept on
 * disk. Bounded so a long-lived project directory can't accumulate an
 * unbounded number of run files (each polled/listed on every list() call).
 * A run in "running" or "paused" status is NEVER counted against this cap
 * or evicted by it — only genuinely finished runs age out, oldest (by
 * updatedAt) first, once the terminal-run count exceeds the cap. 300 is
 * generous enough to cover weeks of typical usage while keeping list()'s
 * per-call directory scan bounded.
 */
export declare const DEFAULT_MAX_TERMINAL_RUNS_ON_DISK = 300;
/**
 * How long a run lock written by ANOTHER host may go unrefreshed before it is
 * treated as dead and reclaimed. Nothing here can inspect a foreign process, so
 * time is the only bound available — and a bound there must be: without one, a
 * lock left behind by a machine that has since been renamed, or by a peer
 * sharing a synced run store, would hold the run forever and no resume, auto-
 * resume or startup reconciliation could ever touch it again. The holder
 * refreshes its heartbeat on every persist (see LOCK_HEARTBEAT_INTERVAL_MS), so
 * a window this wide is only reached by a run that stopped reporting progress
 * entirely.
 */
export declare const DEFAULT_FOREIGN_LOCK_STALE_MS: number;
export interface RunPersistenceOptions {
    /** Override DEFAULT_MAX_TERMINAL_RUNS_ON_DISK (tests; advanced tuning). */
    maxTerminalRunsOnDisk?: number;
    /**
     * Override DEFAULT_FOREIGN_LOCK_STALE_MS (tests; shared/synced run stores).
     * Clamped to at least MIN_FOREIGN_LOCK_STALE_MS.
     */
    foreignLockStaleMs?: number;
}
/** Whether `runId` is safe to turn into a path inside a run store. */
export declare function isSafeRunId(runId: unknown): runId is string;
/**
 * Project a parsed run file onto PersistedRunState, field by field.
 *
 * Run records are read from the global store AND from a project-local store
 * (`<cwd>/.pi/workflows/runs`, see WorkflowProjectPaths.legacyRunsDir), and a
 * project-local store is part of whatever repository happens to be checked
 * out. Since a record's `script` is what resume() executes, a run file is
 * untrusted input, not this module's own output: unknown fields are dropped,
 * a known field of the wrong type rejects the whole record, and provenance
 * (`sourcePath`/`sourceStore`) is assigned by the caller, never believed from
 * the file. Returns the reason on rejection so the caller can say so loudly.
 */
export declare function validatePersistedRunState(value: unknown): {
    state: PersistedRunState;
} | {
    reason: string;
};
/**
 * Whether this install wrote this record and it lives in the global run store.
 * Both halves matter: the store location is unforgeable (nothing outside this
 * process writes there) and the install id is unguessable, so a run file that
 * travelled in with a repository satisfies neither.
 */
export declare function isInstallOwnedRun(run: PersistedRunState, installId: string): boolean;
/**
 * Where a run's script came from when it is not this install's own work: the
 * project-local file it was read from, or the marker a relocated record carries
 * (see PersistedRunState.foreignSource). undefined means the script was written
 * by this install into its own store. Callers that copy a run's script somewhere
 * more durable — `/workflows save`, the navigator's save action — carry this
 * with it so a repo-supplied script does not become trusted by being saved.
 */
export declare function runScriptOrigin(run: PersistedRunState): string | undefined;
/**
 * Whether a persisted run may be resumed with no human in the loop (see
 * UsageLimitScheduler). Auto-resume executes `script`, so it is restricted to
 * runs this install created; anything else stays listable, inspectable, and
 * resumable by explicit user action.
 */
export declare function isAutoResumeEligibleRun(run: PersistedRunState, installId: string): boolean;
export declare function createRunPersistence(cwd: string, fsOverride?: Partial<FsLayer>, options?: RunPersistenceOptions): RunPersistence;
/**
 * Generate a unique run ID.
 */
export declare function generateRunId(): string;
