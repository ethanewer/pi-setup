/**
 * Filesystem layout for pi-dynamic-workflows state.
 *
 * New writes live under the user's workflow home so projects do not get
 * scattered `.pi/workflows` directories. Project-scoped state is still isolated
 * by a stable cwd-derived namespace.
 */
export declare const WORKFLOW_HOME_RELATIVE_DIR = ".pi/workflows";
export declare const WORKFLOW_PROJECTS_SUBDIR = "projects";
export declare const WORKFLOW_INSTALL_ID_FILE = "install-id";
export interface WorkflowProjectPaths {
    key: string;
    rootDir: string;
    runsDir: string;
    savedDir: string;
    settingsPath: string;
    legacyRunsDir: string;
    legacySavedDir: string;
}
export declare function workflowHomeDir(): string;
export declare function workflowUserSavedDir(): string;
export declare function workflowProjectKey(cwd: string): string;
/**
 * Opaque identity of this workflow home, generated once and kept in
 * `~/.pi/workflows/install-id`. Run files record it so state this install never
 * wrote — a run store that arrived inside a cloned repository, say — is never
 * mistaken for a run of ours and auto-resumed. Unguessable by design: a value
 * derived from public facts (username, paths) could be reproduced by whoever
 * authored such a file. Falls back to a path-derived digest, and never throws,
 * when the home directory is not writable; a fallback id is still stable for
 * this install and still differs from "absent".
 */
export declare function workflowInstallId(): string;
export declare function workflowProjectPaths(cwd: string): WorkflowProjectPaths;
