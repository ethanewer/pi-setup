/**
 * Purpose: Own which upstream `agent-browser` executable the wrapper spawns and which parent environment variables reach it.
 * Responsibilities: Resolve and pin the CLI file, reject workspace-local PATH resolutions, strip workspace-local PATH entries from the child, and drop loader/interpreter injection variables.
 * Scope: Pure spawn-input policy; process lifecycle, stdout spilling, and argv planning stay in process.js.
 * Invariants/Assumptions: Only user-owned environment variables widen the policy, an unresolvable name still falls back to the bare executable name so the spawn reports its own ENOENT, and every denied variable stays denied unless the operator forwards the whole environment.
 */
import { statSync } from "node:fs";
import { delimiter, isAbsolute, join, relative, resolve, sep } from "node:path";
export const AGENT_BROWSER_CLI_PATH_ENV = "PI_AGENT_BROWSER_CLI_PATH";
export const WORKSPACE_CLI_ENV = "PI_AGENT_BROWSER_ALLOW_WORKSPACE_CLI";
export const FORWARD_ALL_ENV = "PI_AGENT_BROWSER_FORWARD_ALL_ENV";
export const AGENT_BROWSER_CLI_FILE_NAME = "agent-browser";
const WINDOWS_CLI_FILE_NAMES = ["agent-browser.cmd", "agent-browser.exe", "agent-browser.bat", "agent-browser.ps1"];
/** Variables that make an unrelated interpreter or loader run caller-chosen code inside the child. */
export const DENIED_CHILD_ENV_VARS = [
    "BUN_INSPECT",
    "BUN_INSPECT_CONNECT_TO",
    "BUN_INSPECT_NOTIFY",
    "DYLD_INSERT_LIBRARIES",
    "ELECTRON_RUN_AS_NODE",
    "LD_AUDIT",
    "LD_PRELOAD",
    "NODE_OPTIONS",
    "NODE_REPL_EXTERNAL_MODULE",
];
function isTruthyEnvValue(value) {
    const normalized = value?.trim().toLowerCase();
    return normalized === "1" || normalized === "true" || normalized === "yes";
}
function pathIsWithin(path, parent) {
    const relativePath = relative(resolve(parent), resolve(path));
    return relativePath.length === 0 || (!relativePath.startsWith("..") && !isAbsolute(relativePath));
}
function hasNodeModulesSegment(path) {
    return resolve(path).split(sep).includes("node_modules");
}
function isExecutableFile(path, platform) {
    let stats;
    try {
        stats = statSync(path);
    }
    catch {
        return false;
    }
    if (!stats.isFile())
        return false;
    return platform === "win32" || (stats.mode & 0o111) !== 0;
}
function getEnvPathValue(env) {
    return env.PATH ?? env.Path ?? env.path;
}
/** @param {NodeJS.ProcessEnv} [env] */
export function isWorkspaceCliAllowed(env = process.env) {
    return isTruthyEnvValue(env[WORKSPACE_CLI_ENV]);
}
/** @param {NodeJS.ProcessEnv} [env] */
export function isFullChildEnvForwardingAllowed(env = process.env) {
    return isTruthyEnvValue(env[FORWARD_ALL_ENV]);
}
/**
 * A PATH entry is workspace-local when it is relative (so it resolves against the child cwd) or when it points
 * into a dependency directory inside the session workspace, which a checked-in `node_modules/.bin` can control.
 * @param {string} entry
 * @param {string | undefined} cwd
 */
export function isWorkspaceLocalPathEntry(entry, cwd) {
    const trimmed = entry.trim();
    if (trimmed.length === 0)
        return false;
    if (!isAbsolute(trimmed))
        return true;
    if (cwd === undefined)
        return false;
    return pathIsWithin(trimmed, cwd) && hasNodeModulesSegment(trimmed);
}
/**
 * @param {string | undefined} pathValue
 * @param {{ cwd?: string; env?: NodeJS.ProcessEnv }} [options]
 */
export function sanitizeChildPathValue(pathValue, options = {}) {
    if (pathValue === undefined)
        return undefined;
    const env = options.env ?? process.env;
    if (options.cwd === undefined || isWorkspaceCliAllowed(env))
        return pathValue;
    const keptEntries = pathValue
        .split(delimiter)
        .filter((entry) => entry.trim().length === 0 || !isWorkspaceLocalPathEntry(entry, options.cwd));
    return keptEntries.join(delimiter);
}
/**
 * Resolves the upstream CLI to a pinned file so `execvp` cannot pick a workspace-local shim.
 * Returns `{}` when nothing matched, leaving the bare executable name to report its own spawn failure.
 * @param {{ cwd?: string; env?: NodeJS.ProcessEnv; platform?: NodeJS.Platform }} [options]
 * @returns {{ path?: string; error?: string }}
 */
export function resolveAgentBrowserCliPath(options = {}) {
    const env = options.env ?? process.env;
    const platform = options.platform ?? process.platform;
    const configuredPath = env[AGENT_BROWSER_CLI_PATH_ENV]?.trim();
    if (configuredPath) {
        if (!isAbsolute(configuredPath))
            return { error: `${AGENT_BROWSER_CLI_PATH_ENV} must be an absolute path, but is ${JSON.stringify(configuredPath)}.` };
        if (!isExecutableFile(configuredPath, platform))
            return { error: `${AGENT_BROWSER_CLI_PATH_ENV}=${configuredPath} does not point to an executable agent-browser CLI file.` };
        return { path: configuredPath };
    }
    const fileNames = platform === "win32" ? WINDOWS_CLI_FILE_NAMES : [AGENT_BROWSER_CLI_FILE_NAME];
    const allowWorkspaceCli = isWorkspaceCliAllowed(env);
    let workspaceLocalCandidate;
    for (const entry of (getEnvPathValue(env) ?? "").split(delimiter)) {
        const directory = entry.trim();
        if (directory.length === 0)
            continue;
        const workspaceLocalEntry = !allowWorkspaceCli && isWorkspaceLocalPathEntry(directory, options.cwd);
        for (const fileName of fileNames) {
            const candidate = isAbsolute(directory)
                ? join(directory, fileName)
                : join(resolve(options.cwd ?? process.cwd(), directory), fileName);
            if (!isExecutableFile(candidate, platform))
                continue;
            if (workspaceLocalEntry) {
                workspaceLocalCandidate ??= candidate;
                continue;
            }
            return { path: candidate };
        }
    }
    if (workspaceLocalCandidate) {
        return {
            error: [
                `Refusing to run the workspace-local agent-browser at ${workspaceLocalCandidate}: policy blocked because it resolves through a workspace PATH entry that the checked-out project controls.`,
                `Install agent-browser outside the workspace, pin it with ${AGENT_BROWSER_CLI_PATH_ENV}=<absolute path>, or set ${WORKSPACE_CLI_ENV}=1 to allow the workspace copy.`,
            ].join(" "),
        };
    }
    return {};
}
