/**
 * `/workflows` slash command: list, inspect, and control background workflow runs.
 * Shares the extension's single WorkflowManager so background runs are reachable.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { type EffortState } from "./effort-command.js";
import type { WorkflowManager } from "./workflow-manager.js";
import type { WorkflowStorage } from "./workflow-saved.js";
export interface WorkflowCommandOptions {
    /** Saved-workflow storage, enabling `/workflows save`. */
    storage?: WorkflowStorage;
    /** Working directory for saved workflows registered via `save`. */
    cwd?: string;
    /** Standing effort mode; when high/ultra, `/workflows run` carries its directive too. */
    effort?: EffortState;
}
/** Register the `/workflows` command against the shared manager. Idempotent. */
export declare function registerWorkflowCommands(pi: ExtensionAPI, manager: WorkflowManager, opts?: WorkflowCommandOptions): void;
