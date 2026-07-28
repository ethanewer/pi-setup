import type { EffortState } from "./effort-command.js";
import type { WorkflowManager } from "./workflow-manager.js";
/**
 * Live extension state that Pi may hand from one extension generation to the
 * next during `/reload`. This deliberately stays process-local: run snapshots
 * and journals already provide the durable cold-start path, while the live
 * manager is what owns in-flight promises, abort controllers, and event streams.
 */
export declare const WORKFLOW_EXTENSION_VERSION: string;
export interface WorkflowReloadRuntime {
    cwd: string;
    /** Package version that created this manager. Only an exact match is retained. */
    extensionVersion: string;
    manager: WorkflowManager;
    effort: EffortState;
}
export interface WorkflowRuntimeClaim {
    compatible?: WorkflowReloadRuntime;
    versionMismatch?: WorkflowReloadRuntime;
}
/**
 * Stage a live runtime immediately before Pi tears down the old extension runner.
 *
 * `ttlMs` is only ever overridden by tests; production callers rely on the
 * default so a slow/failed reload doesn't strand a staged runtime forever.
 */
export declare function handoffWorkflowRuntime(runtime: WorkflowReloadRuntime, ttlMs?: number): void;
/** Claim a staged runtime from the extension generation that `/reload` just stopped. */
export declare function takeWorkflowRuntime(cwd: string): WorkflowReloadRuntime | undefined;
/**
 * Claim a staged runtime and compare its package version with this extension
 * generation. Any package update falls back to a fresh manager; only reloads
 * within the exact same installed version retain live workflow state.
 */
export declare function claimWorkflowRuntime(cwd: string): WorkflowRuntimeClaim;
/**
 * Move a runtime's live runs onto the existing journal recovery path when no
 * compatible manager will carry them forward — a replaced extension version,
 * or a staged handoff that expired unclaimed.
 */
export declare function pauseStrandedWorkflowRuntime(runtime: WorkflowReloadRuntime): number;
/** Test/cleanup helper; identity guard avoids deleting a newer handoff. */
export declare function discardWorkflowRuntime(cwd: string, runtime?: WorkflowReloadRuntime): void;
