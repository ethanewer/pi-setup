/**
 * Saved workflows as `/<name>` slash commands. Each saved workflow becomes a
 * command that runs its script, passing parsed arguments through as `args`.
 */
import { type ExtensionAPI, type ExtensionCommandContext } from "@earendil-works/pi-coding-agent";
import type { WorkflowManager } from "./workflow-manager.js";
import type { SavedWorkflow, WorkflowStorage } from "./workflow-saved.js";
/**
 * Pi cannot unregister a slash command. Distinguish commands this extension
 * owns from built-ins/other extensions before a save or rename reaches disk.
 */
export declare function savedWorkflowCommandAvailability(pi: ExtensionAPI, name: string): {
    ok: true;
} | {
    ok: false;
    message: string;
};
/**
 * Ask before running a workflow whose script came from the project rather than
 * from the user. The prompt names the exact source: a repository can ship
 * `.pi/workflows/saved/<name>.json`, and cloning it must not be enough to make
 * `/<name>` start subagents — nor must copying a project-supplied run's script
 * into the user's own storage (see SavedWorkflow.scriptOrigin), which is why a
 * recorded origin gates the same way a repo-local file does. Declining is not an
 * error — it just doesn't run. Answered yes-by-configuration via
 * trustProjectLocalWorkflows.
 */
export declare function confirmRepoLocalWorkflow(ctx: ExtensionCommandContext, wf: Pick<SavedWorkflow, "name" | "path" | "repoLocal" | "scriptOrigin">, cwd: string, purpose?: string): Promise<boolean>;
export declare function parseCommandArgs(raw: string, parameters?: SavedWorkflow["parameters"]): Record<string, unknown>;
/** Register one saved workflow as a dynamically loaded slash command. */
export declare function registerSavedWorkflow(pi: ExtensionAPI, cwd: string | (() => string), wf: Pick<SavedWorkflow, "name" | "description" | "script" | "parameters" | "path" | "repoLocal" | "scriptOrigin">, manager?: WorkflowManager | (() => WorkflowManager | undefined), exists?: () => boolean, loadWorkflow?: () => Pick<SavedWorkflow, "name" | "description" | "script" | "parameters" | "path" | "repoLocal" | "scriptOrigin"> | null | undefined): {
    ok: true;
} | {
    ok: false;
    message: string;
};
export declare function registerAllSavedWorkflows(pi: ExtensionAPI, cwd: string | (() => string), storage: WorkflowStorage | (() => WorkflowStorage), manager?: WorkflowManager | (() => WorkflowManager | undefined)): void;
