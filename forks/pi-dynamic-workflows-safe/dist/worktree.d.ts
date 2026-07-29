/**
 * Per-agent git worktree isolation. When an agent requests `isolation: "worktree"`,
 * it runs in a throwaway worktree on its own branch so parallel agents can edit the
 * same files without conflict. Results are NOT auto-merged — the path is surfaced for
 * the caller to inspect. Falls back to a logged no-op when isolation isn't possible.
 */
export interface Worktree {
    /** True when a real worktree was created; false means "ran in the shared tree". */
    isolated: boolean;
    /** cwd the agent should run in (worktree path when isolated, else the base cwd). */
    cwd: string;
    branch?: string;
    /** Repo root the worktree was added to (for teardown). */
    repoRoot?: string;
    /** Why isolation was skipped, when isolated === false. */
    reason?: string;
    /**
     * True when `baseCwd` is not inside a git repository at all, i.e. worktree
     * isolation was never available here — as opposed to a repository where
     * `git worktree add` itself failed. The caller's fallback policy differs
     * between the two (see WorkflowRunOptions.isolationFallback).
     */
    noRepository?: boolean;
}
/**
 * Directory/branch id for a worktree. The readable slug is truncated, and the
 * names passed in (`<runId>-<callIndex>-<label>`) share a long runId prefix, so
 * the slug ALONE collides across agents of the same run — every colliding agent
 * but the first would fail `git worktree add` and fall back to the shared tree,
 * i.e. silently lose the isolation the caller asked for. The full name's digest
 * is what makes the id unique; it stays deterministic, so resume keys are stable.
 */
export declare function worktreeId(name: string): string;
/**
 * Create an isolated worktree under `<repoRoot>/.pi/worktrees/<id>` on branch
 * `pi/wf/<id>`. The `name` must be deterministic (derived from runId + call index,
 * never wall-clock) so resume keys stay stable. Returns a no-op Worktree carrying
 * the reason on failure; the CALLER decides whether running unisolated is
 * acceptable (see WorkflowRunOptions.isolationFallback) — it never is by default.
 */
export declare function createWorktree(baseCwd: string, name: string): Promise<Worktree>;
/** Remove a worktree and its branch. Best-effort; safe to call on a no-op Worktree. */
export declare function removeWorktree(wt: Worktree): Promise<void>;
