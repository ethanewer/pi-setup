/**
 * Filesystem layout for pi-dynamic-workflows state.
 *
 * New writes live under the user's workflow home so projects do not get
 * scattered `.pi/workflows` directories. Project-scoped state is still isolated
 * by a stable cwd-derived namespace.
 */
import { createHash, randomUUID } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { basename, join, resolve } from "node:path";
import { WORKFLOW_RUNS_DIR, WORKFLOW_SAVED_DIR } from "./config.js";
import { PRIVATE_DIR_MODE, PRIVATE_FILE_MODE } from "./fs-persistence.js";
export const WORKFLOW_HOME_RELATIVE_DIR = ".pi/workflows";
export const WORKFLOW_PROJECTS_SUBDIR = "projects";
export const WORKFLOW_INSTALL_ID_FILE = "install-id";
export function workflowHomeDir() {
    return join(homedir(), WORKFLOW_HOME_RELATIVE_DIR);
}
export function workflowUserSavedDir() {
    return join(workflowHomeDir(), "saved");
}
export function workflowProjectKey(cwd) {
    const projectPath = resolve(cwd);
    const slug = sanitizePathSegment(basename(projectPath) || "project");
    const hash = createHash("sha256").update(projectPath).digest("hex").slice(0, 12);
    return `${slug}-${hash}`;
}
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
export function workflowInstallId() {
    if (cachedInstallId)
        return cachedInstallId;
    const path = join(workflowHomeDir(), WORKFLOW_INSTALL_ID_FILE);
    try {
        if (existsSync(path)) {
            const existing = readFileSync(path, "utf-8").trim();
            if (existing.length > 0 && existing.length <= 200) {
                cachedInstallId = existing;
                return existing;
            }
        }
        const minted = randomUUID();
        // The workflow home is usually created here first, so it gets the same
        // owner-only mode as the run/saved stores nested inside it — otherwise a
        // fresh install left the directory holding scripts, prompts and results
        // world-readable (mode applies only to what this call creates).
        mkdirSync(workflowHomeDir(), { recursive: true, mode: PRIVATE_DIR_MODE });
        // Owner-only: the id is a capability (it is what marks a run as ours and
        // therefore auto-resumable), so it must not be readable by other accounts —
        // same reason every record this package writes is 0600 (fs-persistence.ts).
        writeFileSync(path, `${minted}\n`, { encoding: "utf-8", mode: PRIVATE_FILE_MODE });
        cachedInstallId = minted;
        return minted;
    }
    catch {
        cachedInstallId = `derived-${createHash("sha256").update(`${homedir()} ${path}`).digest("hex").slice(0, 32)}`;
        return cachedInstallId;
    }
}
export function workflowProjectPaths(cwd) {
    const key = workflowProjectKey(cwd);
    const rootDir = join(workflowHomeDir(), WORKFLOW_PROJECTS_SUBDIR, key);
    return {
        key,
        rootDir,
        runsDir: join(rootDir, "runs"),
        savedDir: join(rootDir, "saved"),
        settingsPath: join(rootDir, "settings.json"),
        legacyRunsDir: resolve(cwd, WORKFLOW_RUNS_DIR),
        legacySavedDir: resolve(cwd, WORKFLOW_SAVED_DIR),
    };
}
let cachedInstallId;
function sanitizePathSegment(value) {
    const sanitized = value
        .toLowerCase()
        .replace(/[^a-z0-9._-]+/g, "-")
        .replace(/^-+|-+$/g, "")
        .slice(0, 48);
    return sanitized || "project";
}
