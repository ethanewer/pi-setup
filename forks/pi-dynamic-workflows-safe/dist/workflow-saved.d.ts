/**
 * Save and load reusable workflow commands.
 */
import { type PersistenceFsLayer } from "./fs-persistence.js";
export type SavedWorkflowSource = "project" | "legacy" | "user";
export interface SavedWorkflow {
    /** Command name (filename without extension). */
    name: string;
    /** Human-readable description. */
    description: string;
    /** The workflow script. */
    script: string;
    /** Optional parameter schema for parameterized workflows. */
    parameters?: Record<string, {
        type: string;
        description?: string;
        required?: boolean;
        default?: unknown;
    }>;
    /** Display location retained for compatibility with existing callers. */
    location: "project" | "user";
    /** Exact persistence tier that supplied this row. */
    source: SavedWorkflowSource;
    /** Full file path. This is part of the row's identity, not display metadata. */
    path: string;
    /** When it was saved. */
    savedAt: string;
    /**
     * True when this workflow was read from the project directory itself
     * (`<cwd>/.pi/workflows/saved`) rather than the user's workflow home, i.e. it
     * came with whatever repository is checked out. Assigned by the reader, never
     * taken from the file. Such a workflow stays listable and runnable, but only
     * behind a confirmation that names this `path` (see
     * WorkflowSettings.trustProjectLocalWorkflows).
     */
    repoLocal?: boolean;
    /**
     * Where this script came from when it was not authored in this install —
     * `/workflows save` and the navigator's save action copy the script out of a
     * run record, and that record may itself have come from the project's own run
     * store (see runScriptOrigin). Unlike `repoLocal`, which describes where the
     * saved FILE was read from, this travels WITH the record: landing in the
     * user's own storage is not what makes a repo-supplied script trustworthy, so
     * the command it becomes stays gated on a confirmation naming this origin.
     */
    scriptOrigin?: string;
}
export type SavedWorkflowMutationResult = {
    ok: true;
    workflow?: SavedWorkflow;
} | {
    ok: false;
    code: "missing" | "stale" | "conflict" | "invalid" | "io-error";
    message: string;
};
/** Stable content fingerprint used to guard mutations against same-path races. */
export declare function savedWorkflowRevision(workflow: Pick<SavedWorkflow, "name" | "description" | "script" | "parameters" | "savedAt">): string;
export interface WorkflowStorage {
    /** Save a workflow. New saves default to the current project tier. */
    save(workflow: Omit<SavedWorkflow, "path" | "savedAt" | "source">, location?: "project" | "user"): SavedWorkflow;
    /** Load a workflow by name according to project > legacy > user precedence. */
    load(name: string): SavedWorkflow | null;
    /** List visible workflows, one highest-precedence row per command name. */
    list(): SavedWorkflow[];
    /** Delete precisely the source represented by the visible row. */
    delete(workflow: SavedWorkflow | string, location?: "project" | "user"): SavedWorkflowMutationResult | boolean;
    /** Rename precisely the source represented by the visible row. */
    rename(workflow: SavedWorkflow, name: string): SavedWorkflowMutationResult;
}
/**
 * Saved workflow names are Pi slash-command names as well as filenames. Keep the
 * validation in one place so `/workflows save`, rename, and command registration
 * have the same reachability boundary. Whitespace, controls, Unicode format
 * characters (including bidi controls), and path separators never form a safe
 * command/file identity.
 */
export declare function isSafeSavedWorkflowName(name: string): boolean;
export declare function assertSafeSavedWorkflowName(name: string): void;
export interface WorkflowStorageOptions {
    /**
     * Resolve project-local saved workflows (`<cwd>/.pi/workflows/saved`) by name
     * without asking anyone. Defaults to WorkflowSettings.trustProjectLocalWorkflows
     * for this cwd, which defaults to false.
     */
    trustRepoLocal?: boolean;
}
export declare function createWorkflowStorage(cwd: string, fsOverride?: Partial<PersistenceFsLayer>, options?: WorkflowStorageOptions): WorkflowStorage;
