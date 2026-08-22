import { AsyncLocalStorage } from "node:async_hooks";
import { spawn } from "node:child_process";
import { lstat, mkdir, readdir } from "node:fs/promises";
import { dirname, isAbsolute, join } from "node:path";
import { env as processEnv, platform as processPlatform } from "node:process";
import { parseArgvDescriptor } from "./argv-descriptor.js";
import { needsManagedSession } from "./command-policy.js";
import { isKnownCommandToken } from "./command-taxonomy.js";
import { extractExplicitSessionName, getFlagName, GLOBAL_BOOLEAN_FLAGS_WITH_OPTIONAL_VALUES, GLOBAL_VALUE_FLAGS, optionalGlobalValueFlagConsumesNext, resolveAgentBrowserNamespace, } from "./argv-grammar.js";
import { canonicalizeOwnedManagedSessionCloseArgs, commitManagedSessionRestoreSuppression, getManagedSessionRestoreConfigEnv, getManagedSessionRestoreEnv, getOwnedManagedSessionRestoreKey, getManagedSessionRestoreProtectedEnv, getOwnedManagedSessionCompatibilityEnv, getOwnedManagedSessionNamespaceEnv, isOwnedManagedSessionTarget, shouldOmitOwnedManagedSessionRestoreEnv, validateManagedSessionRestoreContextForSpawn, } from "./managed-session-restore.js";
import { getManagedSessionStateAccessValidationError, getManagedSessionTargetAccessValidationError, invocationMayNavigateToLocalFile, } from "./managed-session-state-policy.js";
import { getImplicitSessionIdleTimeoutMs, isPlainTextInspectionArgs } from "./runtime.js";
import { getAgentBrowserProcessEnvironment } from "./process-environment.js";
import { openSecureTempFile, writeSecureTempChunk } from "./temp.js";
import { DENIED_CHILD_ENV_VARS, isFullChildEnvForwardingAllowed, resolveAgentBrowserCliPath, sanitizeChildPathValue, } from "./child-process-policy.js";
import { UPSTREAM_CONFIG_ENV, getUpstreamConfigPinFailureError, planUpstreamConfigPin, } from "./upstream-config-policy.js";
const MAX_BUFFERED_STDOUT_BYTES = 512 * 1_024;
const MAX_BUFFERED_STDERR_CHARS = 32_000;
const MAX_BUFFERED_STDOUT_TAIL_CHARS = 32_000;
const PROCESS_STDOUT_SPILL_FILE_PREFIX = "process-stdout";
const AGENT_BROWSER_SOCKET_DIR_ENV = "AGENT_BROWSER_SOCKET_DIR";
const AGENT_BROWSER_ARGS_ENV = "AGENT_BROWSER_ARGS";
const AGENT_BROWSER_DEFAULT_TIMEOUT_ENV = "AGENT_BROWSER_DEFAULT_TIMEOUT";
const AGENT_BROWSER_IDLE_TIMEOUT_ENV = "AGENT_BROWSER_IDLE_TIMEOUT_MS";
const PI_AGENT_BROWSER_PROCESS_TIMEOUT_ENV = "PI_AGENT_BROWSER_PROCESS_TIMEOUT_MS";
const PI_AGENT_BROWSER_SOCKET_DIR_ENV = "PI_AGENT_BROWSER_SOCKET_DIR";
const DEFAULT_AGENT_BROWSER_SOCKET_DIR_PREFIX = "/tmp/piab";
const TERMUX_PACKAGE_NAME_PATTERN = /^[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)+$/;
export const SAFE_AGENT_BROWSER_OPERATION_TIMEOUT_MS = 25_000;
const DEFAULT_AGENT_BROWSER_PROCESS_TIMEOUT_MS = 35_000;
/** Grace period after `exit` before resolving when `close` is delayed by inherited stdio handles. */
const EXIT_STDIO_GRACE_MS = 100;
const UPSTREAM_CONFIG_PIN_FILE_PREFIX = "upstream-config";
/** Grace period after SIGTERM before the process group is escalated to SIGKILL. */
const CHILD_TERMINATION_ESCALATION_MS = 2_000;
const WINDOWS_AGENT_BROWSER_MISSING_MARKER = "PI_AGENT_BROWSER_COMMAND_NOT_FOUND:agent-browser.cmd";
const UNTRUSTED_LOCAL_FILE_SESSION_MESSAGE = "Local file navigation requires a wrapper-managed local browser because caller-owned or attached sessions can retain unsafe file-access launch flags. Omit the explicit session or attachment and retry with sessionMode fresh.";
const attachedBrowserSessionContext = new AsyncLocalStorage();
const WINDOWS_COMMANDS_WITH_ADJACENT_SUBCOMMAND = new Set([
    "auth", "clipboard", "cookies", "dashboard", "device", "dialog", "diff", "find", "get", "is", "keyboard",
    "mouse", "network", "plugin", "profiler", "react", "record", "session", "set", "skills", "state", "storage",
    "stream", "tab", "trace", "window",
]);
export function withAttachedBrowserSessionContext(preserve, run) {
    return attachedBrowserSessionContext.run(preserve || attachedBrowserSessionContext.getStore() === true, run);
}
export function getWindowsExplicitDefaultNamespaceEnv(args, parentNamespace, platform = processPlatform) {
    return platform === "win32" && resolveAgentBrowserNamespace(args, parentNamespace) === ""
        ? { AGENT_BROWSER_NAMESPACE: "" }
        : {};
}
function appendTail(text, addition, maxChars) {
    const combined = text + addition;
    return combined.length <= maxChars ? combined : combined.slice(combined.length - maxChars);
}
function quoteWindowsPowerShellArg(value) {
    return `'${value.replace(/'/g, "''")}'`;
}
/** Exported for unit tests that lock Windows launcher argv ordering. */
export function reorderWindowsLeadingGlobalArgs(args) {
    const leadingGlobals = [];
    for (let index = 0; index < args.length; index += 1) {
        const token = args[index];
        if (isKnownCommandToken(token)) {
            if (index === 0)
                return args;
            const firstPositional = args[index + 1];
            return WINDOWS_COMMANDS_WITH_ADJACENT_SUBCOMMAND.has(token) && firstPositional && !firstPositional.startsWith("-")
                ? [token, firstPositional, ...leadingGlobals, ...args.slice(index + 2)]
                : [token, ...leadingGlobals, ...args.slice(index + 1)];
        }
        if (!token.startsWith("-"))
            return args;
        if (token.startsWith("--restore=")) {
            leadingGlobals.push(token);
            continue;
        }
        if (token === "--restore") {
            const value = args[index + 1];
            if (optionalGlobalValueFlagConsumesNext(token, value)) {
                leadingGlobals.push(`--restore=${value}`);
                index += 1;
            }
            else {
                leadingGlobals.push(token);
            }
            continue;
        }
        if (token.includes("="))
            return args;
        const flag = getFlagName(token);
        if (GLOBAL_BOOLEAN_FLAGS_WITH_OPTIONAL_VALUES.has(flag)) {
            leadingGlobals.push(token);
            if (["true", "false"].includes(args[index + 1] ?? "")) {
                leadingGlobals.push(args[index + 1]);
                index += 1;
            }
            continue;
        }
        if (GLOBAL_VALUE_FLAGS.includes(flag)) {
            const value = args[index + 1];
            if (value === undefined)
                return args;
            // PowerShell -> .cmd drops empty argv values. Planning rejects empty
            // caller --args; keep this defensive skip so an unexpected empty value
            // cannot turn the next flag into its accidental value on native Windows.
            if (value === "" && (flag === "--args" || flag === "--namespace")) {
                index += 1;
                continue;
            }
            leadingGlobals.push(token, value);
            index += 1;
            continue;
        }
        return args;
    }
    return args;
}
export function pinAgentBrowserFileAccessDisabled(args, wrapperCompatibilityUserAgent, preserveAttachedBrowserSession = false) {
    const filtered = [];
    for (let index = 0; index < args.length; index += 1) {
        const token = args[index];
        if (token.startsWith("--allow-file-access="))
            continue;
        if (token === "--allow-file-access") {
            if (["false", "true"].includes(args[index + 1] ?? ""))
                index += 1;
            continue;
        }
        filtered.push(token);
    }
    // These are launch-only controls. Sending them on an attached-session follow-up makes upstream replace the CDP connection with a local browser.
    if (preserveAttachedBrowserSession)
        return filtered;
    // Upstream's flag overrides only the active CDP target; the Chrome arg covers new tabs. Its --args parser splits commas/newlines.
    const browserArgs = wrapperCompatibilityUserAgent
        ? ["--args", `--user-agent=${wrapperCompatibilityUserAgent.replaceAll(/[\r\n,]/g, "")}`]
        : [];
    return [...browserArgs, "--allow-file-access", "false", ...filtered];
}
export function buildAgentBrowserSpawnCommand(args, platform = processPlatform, options = {}) {
    // The CLI is pinned to a resolved file rather than left to PATH lookup, so a
    // workspace-local `agent-browser` shim cannot take over the child.
    const resolvedCli = resolveAgentBrowserCliPath({ cwd: options.cwd, env: options.env, platform });
    if (platform !== "win32") {
        return { command: resolvedCli.path ?? "agent-browser", args, error: resolvedCli.error };
    }
    const invocationArgs = reorderWindowsLeadingGlobalArgs(args).map(quoteWindowsPowerShellArg).join(" ");
    // Upstream's Get-Command probe stays as the fallback when nothing was pinned, so its
    // missing-command marker and isWindowsAgentBrowserCommandMissing still work.
    const commandLine = resolvedCli.path
        ? ["&", quoteWindowsPowerShellArg(resolvedCli.path), invocationArgs].join(" ").trimEnd()
        : [
            "$agentBrowser = Get-Command agent-browser.cmd -ErrorAction SilentlyContinue;",
            `if (-not $agentBrowser) { [Console]::Error.WriteLine('${WINDOWS_AGENT_BROWSER_MISSING_MARKER}'); exit 127 };`,
            `& $agentBrowser.Source ${invocationArgs}`.trimEnd(),
        ].join(" ");
    return { command: "powershell.exe", args: ["-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", commandLine], error: resolvedCli.error };
}
export function isWindowsAgentBrowserCommandMissing(stderr) {
    const normalized = stderr.toLowerCase();
    return normalized.includes(WINDOWS_AGENT_BROWSER_MISSING_MARKER.toLowerCase()) || (normalized.includes("agent-browser.cmd") && (normalized.includes("commandnotfoundexception") ||
        normalized.includes("not recognized as the name of a cmdlet") ||
        normalized.includes("not recognized as an internal or external command")));
}
export function shouldCommitManagedRestoreAfterWindowsProcess(input) {
    return !input.spawnError && !(input.exitCode !== 0 && isWindowsAgentBrowserCommandMissing(input.stderr));
}
function terminateSpawnedChild(child, signal) {
    if (processPlatform === "win32" && child.pid) {
        const killer = spawn("taskkill.exe", ["/PID", String(child.pid), "/T", "/F"], { stdio: "ignore" });
        killer.on("error", () => undefined);
        killer.unref();
        child.kill(signal);
        return;
    }
    // The child leads its own POSIX process group, so signal the group to reach descendants holding the stdio pipes.
    if (child.pid) {
        try {
            process.kill(-child.pid, signal);
            return;
        }
        catch {
            // Group already gone or never created; fall back to the direct child signal.
        }
    }
    child.kill(signal);
}
/** Exported for unit tests that lock subprocess exit-code precedence. */
export function resolveSpawnedChildExitCode(input) {
    // Precedence: observed `close` code when present, then wrapper timeout (124), then
    // post-`exit` fallback when inherited stdio delays `close`, then spawn failure (127).
    if (input.closeCode !== null && input.closeCode !== undefined) {
        return input.closeCode;
    }
    if (input.timedOut) {
        return 124;
    }
    if (input.useExitFallback && input.exitCode !== null && input.exitCode !== undefined) {
        return input.exitCode;
    }
    return input.spawnError ? 127 : 0;
}
function watchSpawnedChildCompletion(child, options) {
    let exited = false;
    let exitCode = null;
    let postExitTimer;
    // `completed` suppresses duplicate exit/close callbacks; `settled` in `finish` guards async spill cleanup.
    let completed = false;
    const complete = (closeCode) => {
        if (completed)
            return;
        completed = true;
        if (postExitTimer) {
            clearTimeout(postExitTimer);
            postExitTimer = undefined;
        }
        const context = options.getContext();
        options.onComplete(resolveSpawnedChildExitCode({
            closeCode,
            exitCode,
            useExitFallback: exited,
            timedOut: context.timedOut,
            spawnError: context.spawnError,
        }));
    };
    child.once("exit", (code) => {
        exited = true;
        exitCode = code;
        postExitTimer = setTimeout(() => {
            destroySpawnedChildStreams(child);
            complete(undefined);
        }, options.graceMs);
        postExitTimer.unref?.();
    });
    child.once("close", (code) => {
        complete(code);
    });
    return {
        clear: () => {
            if (postExitTimer) {
                clearTimeout(postExitTimer);
                postExitTimer = undefined;
            }
        },
    };
}
function destroySpawnedChildStreams(child) {
    child.stdin?.destroy();
    child.stdout?.destroy();
    child.stderr?.destroy();
}
function parsePositiveIntegerEnv(value) {
    if (value === undefined || !/^\d+$/.test(value.trim())) {
        return undefined;
    }
    const parsed = Number(value.trim());
    return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : undefined;
}
function clampUpstreamDefaultTimeout(childEnv) {
    const requestedTimeout = parsePositiveIntegerEnv(childEnv[AGENT_BROWSER_DEFAULT_TIMEOUT_ENV]);
    if (requestedTimeout === undefined || requestedTimeout > SAFE_AGENT_BROWSER_OPERATION_TIMEOUT_MS) {
        childEnv[AGENT_BROWSER_DEFAULT_TIMEOUT_ENV] = String(SAFE_AGENT_BROWSER_OPERATION_TIMEOUT_MS);
    }
}
export function getAgentBrowserProcessTimeoutMs(env = processEnv) {
    return parsePositiveIntegerEnv(env[PI_AGENT_BROWSER_PROCESS_TIMEOUT_ENV]) ?? DEFAULT_AGENT_BROWSER_PROCESS_TIMEOUT_MS;
}
export function getAgentBrowserSocketDir(platform = processPlatform, uid = typeof process.getuid === "function" ? process.getuid() : undefined, termuxPackageName = processEnv.TERMUX_APP__PACKAGE_NAME) {
    if (platform === "win32") {
        return undefined;
    }
    const termuxAppRoot = platform === "android" && termuxPackageName && TERMUX_PACKAGE_NAME_PATTERN.test(termuxPackageName);
    const prefix = platform === "darwin"
        ? "/private/tmp/piab"
        : termuxAppRoot
            ? `/data/data/${termuxPackageName}/piab`
            : DEFAULT_AGENT_BROWSER_SOCKET_DIR_PREFIX;
    return `${prefix}${!termuxAppRoot && typeof uid === "number" ? `-${uid}` : ""}`;
}
export function isTrustedAndroidAppDataRoot(path, metadata, uid, platform = processPlatform) {
    if (platform !== "android" || metadata.uid !== uid || metadata.isSymbolicLink() || !metadata.isDirectory() || (metadata.mode & 0o777) !== 0o700)
        return false;
    const parent = dirname(path);
    return parent === "/data/data" || /^\/data\/user\/\d+$/.test(parent);
}
export function isTrustedSocketDirAncestor(metadata, uid, platform = processPlatform) {
    if (metadata.isSymbolicLink())
        return metadata.uid === 0;
    if (!metadata.isDirectory())
        return false;
    const mode = metadata.mode & 0o7777;
    if (platform === "android" && uid !== 0 && metadata.uid === uid && metadata.gid === uid)
        return (mode & 0o002) === 0;
    if (metadata.uid === uid && uid !== 0)
        return (mode & 0o022) === 0;
    return metadata.uid === 0 && ((mode & 0o022) === 0 || (mode & 0o1000) !== 0);
}
async function hasTrustedSocketDirAncestry(socketDir, uid) {
    for (let current = dirname(socketDir);;) {
        const metadata = await lstat(current);
        if (isTrustedAndroidAppDataRoot(current, metadata, uid))
            return true;
        if (!isTrustedSocketDirAncestor(metadata, uid))
            return false;
        const parent = dirname(current);
        if (parent === current)
            return true;
        current = parent;
    }
}
async function socketDirEntriesAreOwned(socketDir, uid, visited = { count: 0 }) {
    for (const name of await readdir(socketDir)) {
        if ((visited.count += 1) > 16_384)
            return false;
        try {
            const path = join(socketDir, name);
            const metadata = await lstat(path);
            if (metadata.uid !== uid || metadata.isSymbolicLink())
                return false;
            if (metadata.isDirectory()) {
                if (!await socketDirEntriesAreOwned(path, uid, visited))
                    return false;
            }
            else if (!metadata.isFile() && !metadata.isSocket()) {
                return false;
            }
        }
        catch (error) {
            if (error.code !== "ENOENT")
                return false;
        }
    }
    return true;
}
export async function getAgentBrowserSocketDirValidationError(socketDir, uid = typeof process.getuid === "function" ? process.getuid() : undefined) {
    if (!isAbsolute(socketDir))
        return "the path is not absolute";
    if (typeof uid !== "number")
        return "POSIX ownership metadata is unavailable";
    try {
        if (!await hasTrustedSocketDirAncestry(socketDir, uid))
            return "an ancestor is writable, foreign-owned, a non-directory, or an untrusted symlink";
        try {
            await mkdir(socketDir, { mode: 0o700 });
        }
        catch (error) {
            if (error.code !== "EEXIST")
                return `the directory could not be created (${error.code ?? "unknown error"})`;
        }
        const metadata = await lstat(socketDir);
        if (!metadata.isDirectory())
            return "the path is not a directory";
        if (metadata.isSymbolicLink())
            return "the directory is a symlink";
        if (metadata.uid !== uid)
            return `the directory is owned by uid ${metadata.uid}, not uid ${uid}`;
        if ((metadata.mode & 0o777) !== 0o700)
            return `the directory mode is ${(metadata.mode & 0o777).toString(8)}, not 700`;
        if (!await hasTrustedSocketDirAncestry(socketDir, uid))
            return "an ancestor became untrusted during validation";
        if (!await socketDirEntriesAreOwned(socketDir, uid))
            return "the directory contains a foreign-owned, symlink, special, or excessively deep entry";
        return undefined;
    }
    catch (error) {
        return `the directory could not be inspected (${error.code ?? "unknown error"})`;
    }
}
export async function ensureAgentBrowserSocketDir(socketDir, uid = typeof process.getuid === "function" ? process.getuid() : undefined) {
    return await getAgentBrowserSocketDirValidationError(socketDir, uid) === undefined;
}
export function getAgentBrowserSocketPathValidationError(options) {
    if ((options.platform ?? processPlatform) === "win32")
        return undefined;
    const descriptor = parseArgvDescriptor(options.args);
    const { command } = descriptor.commandInfo;
    // Preflight commands that can start or navigate a browser. Follow-up reads and
    // cleanup may target a daemon created by an earlier wrapper version, so let
    // upstream inspect those identities instead of rejecting them from path math.
    if (!command || !["batch", "connect", "goto", "navigate", "open", "visit"].includes(command))
        return undefined;
    const sessionName = extractExplicitSessionName(options.args);
    if (!sessionName)
        return undefined;
    const namespace = resolveAgentBrowserNamespace(options.args, options.env?.AGENT_BROWSER_NAMESPACE);
    const socketRoot = namespace ? join(options.socketDir, "namespaces", namespace, "run") : options.socketDir;
    const socketPath = join(socketRoot, `${sessionName}.sock`);
    const pathBytes = Buffer.byteLength(socketPath);
    if (pathBytes <= 103)
        return undefined;
    return `Agent-browser Unix socket path would be ${pathBytes} bytes (max 103) for session ${JSON.stringify(sessionName)} under ${JSON.stringify(options.socketDir)}. Set PI_AGENT_BROWSER_SOCKET_DIR to a shorter absolute private directory such as /tmp/piab-<uid> with mode 0700; retrying sessionMode \"fresh\" cannot shorten this configured root.`;
}
export function buildAgentBrowserProcessEnv(baseEnv = processEnv, overrides = undefined, options = {}) {
    const forwardAllEnv = isFullChildEnvForwardingAllowed(baseEnv);
    const childEnv = {};
    for (const [name, value] of Object.entries(baseEnv)) {
        if (value === undefined)
            continue;
        if (!forwardAllEnv && DENIED_CHILD_ENV_VARS.includes(name))
            continue;
        childEnv[name] = value;
    }
    for (const [name, value] of Object.entries(overrides ?? {})) {
        if (value === undefined) {
            delete childEnv[name];
        }
        else {
            childEnv[name] = value;
        }
    }
    if (!forwardAllEnv) {
        for (const name of ["PATH", "Path", "path"]) {
            const sanitizedPath = sanitizeChildPathValue(childEnv[name], { cwd: options.cwd, env: baseEnv });
            if (sanitizedPath !== undefined)
                childEnv[name] = sanitizedPath;
        }
    }
    clampUpstreamDefaultTimeout(childEnv);
    return childEnv;
}
function getManagedPreSpawnPolicyError(options, effectiveEnv, allowManagedSessionTarget = false, currentPageUrl, pageUrlUnknown = false, trustedFirstBatchTabSelection = false, trustedPinnedEmptyConfig = false) {
    const policyEnv = effectiveEnv ?? { ...(options.parentEnv ?? processEnv), ...options.env };
    const managedSessionTargetError = getManagedSessionTargetAccessValidationError(options.args, allowManagedSessionTarget || options.ownedManagedSession === true || isOwnedManagedSessionTarget(options.args), policyEnv);
    if (managedSessionTargetError)
        return managedSessionTargetError;
    if (!validateManagedSessionRestoreContextForSpawn(options)) {
        return "Managed session restore policy, storage, or checkout identity changed after planning; refusing to start agent-browser.";
    }
    return getManagedSessionStateAccessValidationError({
        args: options.args,
        currentPageUrl,
        cwd: options.cwd,
        env: effectiveEnv ?? options.env,
        managedSessionRestoreKey: getOwnedManagedSessionRestoreKey(),
        pageUrlUnknown,
        parentEnv: effectiveEnv ? {} : options.parentEnv ?? processEnv,
        stdin: options.stdin,
        trustedFirstBatchTabSelection,
        trustedPinnedEmptyConfig,
    });
}
export async function runAgentBrowserProcess(options) {
    const { allowManagedSessionTarget, cwd, env, managedSessionRestoreState, managedStateCurrentPageUrl, managedStatePageUrlUnknown, signal, stdin, trustedFirstBatchTabSelection } = options;
    const preserveAttachedBrowserSession = options.preserveAttachedBrowserSession === true || attachedBrowserSessionContext.getStore() === true;
    const ownedManagedSession = options.ownedManagedSession === true || isOwnedManagedSessionTarget(options.args);
    const args = canonicalizeOwnedManagedSessionCloseArgs({
        args: options.args,
        cwd,
        env,
        ownedManagedSession,
        restoreState: managedSessionRestoreState,
        stdin,
    });
    const timeoutMs = options.timeoutMs ?? getAgentBrowserProcessTimeoutMs();
    if (signal?.aborted) {
        return { aborted: true, agentBrowserStarted: false, exitCode: 1, stderr: "", stdout: "", timedOut: false };
    }
    if (invocationMayNavigateToLocalFile(args, stdin) && (!ownedManagedSession || preserveAttachedBrowserSession)) {
        return {
            aborted: false,
            agentBrowserStarted: false,
            exitCode: 1,
            spawnError: new Error(UNTRUSTED_LOCAL_FILE_SESSION_MESSAGE),
            stderr: "",
            stdout: "",
            timedOut: false,
        };
    }
    const parentEnv = getAgentBrowserProcessEnvironment();
    const managedSessionRestoreOptions = {
        args,
        cwd,
        env,
        ownedManagedSession,
        parentEnv,
        restoreState: managedSessionRestoreState,
        stdin,
    };
    const planningPolicyError = getManagedPreSpawnPolicyError(managedSessionRestoreOptions, undefined, allowManagedSessionTarget, managedStateCurrentPageUrl, managedStatePageUrlUnknown, trustedFirstBatchTabSelection);
    if (planningPolicyError) {
        return {
            aborted: false,
            agentBrowserStarted: false,
            exitCode: 1,
            spawnError: new Error(planningPolicyError),
            stderr: "",
            stdout: "",
            timedOut: false,
        };
    }
    const managedSessionRestoreEnv = getManagedSessionRestoreEnv(managedSessionRestoreOptions);
    const ownedManagedSessionClose = shouldOmitOwnedManagedSessionRestoreEnv(managedSessionRestoreOptions);
    const browserConfigPinRequired = !isPlainTextInspectionArgs(args) && needsManagedSession(parseArgvDescriptor(args));
    const managedSessionRestoreConfigEnv = await getManagedSessionRestoreConfigEnv(managedSessionRestoreEnv, ownedManagedSessionClose || browserConfigPinRequired);
    if (managedSessionRestoreConfigEnv === undefined) {
        return {
            aborted: false,
            agentBrowserStarted: false,
            exitCode: 1,
            spawnError: new Error("Browser-backed agent-browser commands require a protected empty config, but secure temp storage was unavailable."),
            stderr: "",
            stdout: "",
            timedOut: false,
        };
    }
    const ownedManagedSessionCompatibilityEnv = getOwnedManagedSessionCompatibilityEnv(managedSessionRestoreOptions);
    const processOverrides = {
        [AGENT_BROWSER_IDLE_TIMEOUT_ENV]: String(getImplicitSessionIdleTimeoutMs()),
        ...managedSessionRestoreEnv,
        ...env,
        ...managedSessionRestoreConfigEnv,
        ...getManagedSessionRestoreProtectedEnv(managedSessionRestoreOptions, managedSessionRestoreEnv),
        ...getOwnedManagedSessionNamespaceEnv(managedSessionRestoreOptions),
        ...getWindowsExplicitDefaultNamespaceEnv(args, parentEnv.AGENT_BROWSER_NAMESPACE),
        ...ownedManagedSessionCompatibilityEnv,
        AGENT_BROWSER_ALLOW_FILE_ACCESS: undefined,
        [AGENT_BROWSER_ARGS_ENV]: undefined,
    };
    const explicitSocketDir = processOverrides[AGENT_BROWSER_SOCKET_DIR_ENV];
    let effectiveEnv = explicitSocketDir === undefined ? { ...processOverrides, [AGENT_BROWSER_SOCKET_DIR_ENV]: undefined } : processOverrides;
    if (ownedManagedSessionClose)
        effectiveEnv = { ...effectiveEnv, AGENT_BROWSER_RESTORE: undefined };
    const requestedSocketDir = explicitSocketDir ?? parentEnv[PI_AGENT_BROWSER_SOCKET_DIR_ENV] ?? getAgentBrowserSocketDir();
    if (requestedSocketDir !== undefined) {
        const socketDirError = requestedSocketDir.length > 0
            ? await getAgentBrowserSocketDirValidationError(requestedSocketDir)
            : "the configured path is empty";
        if (signal?.aborted) {
            return { aborted: true, agentBrowserStarted: false, exitCode: 1, stderr: "", stdout: "", timedOut: false };
        }
        const socketPathError = socketDirError ? undefined : getAgentBrowserSocketPathValidationError({ args, env: effectiveEnv, socketDir: requestedSocketDir });
        if (socketDirError || socketPathError) {
            return {
                aborted: false,
                agentBrowserStarted: false,
                exitCode: 1,
                spawnError: new Error(socketPathError ?? `Agent-browser socket storage ${JSON.stringify(requestedSocketDir)} is unusable: ${socketDirError}. Use an absolute directory owned by the current uid with mode 0700 and remove foreign, symlink, or special entries.`),
                stderr: "",
                stdout: "",
                timedOut: false,
            };
        }
        effectiveEnv = { ...effectiveEnv, [AGENT_BROWSER_SOCKET_DIR_ENV]: requestedSocketDir };
    }
    // Upstream discovers `./agent-browser.json` in the child cwd, so an untrusted project file is replaced by a
    // wrapper-owned pin before the child can read it; an unavailable pin fails the run instead of letting it apply.
    // Since 0.2.74 upstream pins its own process-private empty config for browser-backed commands, and its
    // trustedPinnedEmptyConfig policy flag is derived from that variable — so ours only applies where upstream
    // pinned nothing (notably plain-text inspection commands), and the two can never overwrite each other.
    if (managedSessionRestoreConfigEnv[UPSTREAM_CONFIG_ENV] === undefined) {
        const upstreamConfigPin = planUpstreamConfigPin({ cwd: cwd ?? process.cwd(), env: processEnv });
        if (upstreamConfigPin.kind === "pin") {
            let pinnedConfigPath;
            try {
                pinnedConfigPath = await ensureUpstreamConfigPinPath(upstreamConfigPin.userConfigPath);
            }
            catch (error) {
                return {
                    aborted: false,
                    agentBrowserStarted: false,
                    exitCode: 127,
                    spawnError: new Error(getUpstreamConfigPinFailureError(upstreamConfigPin, error)),
                    stderr: "",
                    stdout: "",
                    timedOut: false,
                };
            }
            effectiveEnv = { ...effectiveEnv, [UPSTREAM_CONFIG_ENV]: pinnedConfigPath };
        }
    }
    if (signal?.aborted) {
        return { aborted: true, agentBrowserStarted: false, exitCode: 1, stderr: "", stdout: "", timedOut: false };
    }
    return await new Promise((resolve) => {
        let aborted = false;
        let agentBrowserStarted = false;
        let settled = false;
        let spawnError;
        let stderr = "";
        let stdoutBuffers = [];
        let stdoutBufferedBytes = 0;
        let stdoutTail = "";
        let stdoutSpillHandle;
        let stdoutSpillPath;
        let pendingStdoutWrite = Promise.resolve();
        let stdoutSpillError;
        let killTimer;
        let timeoutTimer;
        let abortListener;
        let timedOut = false;
        let completionWatcher;
        const queueStdoutChunk = (buffer) => {
            stdoutTail = appendTail(stdoutTail, buffer.toString("utf8"), MAX_BUFFERED_STDOUT_TAIL_CHARS);
            if (stdoutSpillError)
                return;
            if (!stdoutSpillPath && stdoutBufferedBytes + buffer.length <= MAX_BUFFERED_STDOUT_BYTES) {
                stdoutBuffers.push(buffer);
                stdoutBufferedBytes += buffer.length;
                return;
            }
            pendingStdoutWrite = pendingStdoutWrite
                .then(async () => {
                if (stdoutSpillError)
                    return;
                if (!stdoutSpillHandle || !stdoutSpillPath) {
                    const tempFile = await openSecureTempFile(PROCESS_STDOUT_SPILL_FILE_PREFIX, ".json");
                    stdoutSpillHandle = tempFile.fileHandle;
                    stdoutSpillPath = tempFile.path;
                    if (stdoutBuffers.length > 0) {
                        await writeSecureTempChunk({
                            content: Buffer.concat(stdoutBuffers),
                            fileHandle: stdoutSpillHandle,
                            path: stdoutSpillPath,
                        });
                        stdoutBuffers = [];
                        stdoutBufferedBytes = 0;
                    }
                }
                await writeSecureTempChunk({ content: buffer, fileHandle: stdoutSpillHandle, path: stdoutSpillPath });
            })
                .catch((error) => {
                stdoutSpillError = error instanceof Error ? error : new Error(String(error));
            });
        };
        const removeAbortListener = () => {
            if (!signal || !abortListener)
                return;
            signal.removeEventListener("abort", abortListener);
            abortListener = undefined;
        };
        const finish = (exitCode) => {
            if (settled)
                return;
            settled = true;
            void pendingStdoutWrite.finally(async () => {
                removeAbortListener();
                if (killTimer) {
                    clearTimeout(killTimer);
                }
                if (timeoutTimer) {
                    clearTimeout(timeoutTimer);
                }
                completionWatcher?.clear();
                if (stdoutSpillHandle) {
                    await stdoutSpillHandle.close().catch(() => undefined);
                }
                const windowsMissingBinary = processPlatform === "win32" && exitCode !== 0 && isWindowsAgentBrowserCommandMissing(stderr);
                if (processPlatform === "win32" && !windowsMissingBinary && !spawnError)
                    agentBrowserStarted = true;
                if (windowsMissingBinary && !spawnError) {
                    spawnError = Object.assign(new Error("spawn agent-browser ENOENT"), { code: "ENOENT" });
                }
                else if (processPlatform === "win32" && shouldCommitManagedRestoreAfterWindowsProcess({ exitCode, spawnError, stderr })) {
                    commitManagedSessionRestoreSuppression(managedSessionRestoreOptions);
                }
                if (!spawnError && stdoutSpillError) {
                    spawnError = stdoutSpillError;
                }
                // Idempotent teardown: streams may already be destroyed by the post-`exit` fallback.
                destroySpawnedChildStreams(child);
                resolve({
                    aborted,
                    agentBrowserStarted,
                    exitCode,
                    spawnError,
                    stderr,
                    stdout: stdoutSpillPath ? stdoutTail : Buffer.concat(stdoutBuffers).toString("utf8"),
                    stdoutSpillPath,
                    timedOut,
                    timeoutMs: timedOut ? timeoutMs : undefined,
                });
            });
        };
        const childEnv = buildAgentBrowserProcessEnv(parentEnv, effectiveEnv, { cwd });
        const spawnPolicyError = getManagedPreSpawnPolicyError(managedSessionRestoreOptions, childEnv, allowManagedSessionTarget, managedStateCurrentPageUrl, managedStatePageUrlUnknown, trustedFirstBatchTabSelection, managedSessionRestoreConfigEnv.AGENT_BROWSER_CONFIG !== undefined);
        if (spawnPolicyError) {
            resolve({ aborted: false, agentBrowserStarted: false, exitCode: 1, spawnError: new Error(spawnPolicyError), stderr: "", stdout: "", timedOut: false });
            return;
        }
        const spawnCommand = buildAgentBrowserSpawnCommand(pinAgentBrowserFileAccessDisabled(args, ownedManagedSessionCompatibilityEnv.AGENT_BROWSER_USER_AGENT, preserveAttachedBrowserSession), processPlatform, { cwd, env: parentEnv });
        if (spawnCommand.error) {
            resolve({ aborted: false, agentBrowserStarted: false, exitCode: 127, spawnError: new Error(spawnCommand.error), stderr: "", stdout: "", timedOut: false });
            return;
        }
        const child = spawn(spawnCommand.command, spawnCommand.args, {
            cwd,
            // Own process group on POSIX so timeout/abort termination reaches upstream descendants.
            detached: processPlatform !== "win32",
            env: childEnv,
            stdio: ["pipe", "pipe", "pipe"],
        });
        if (processPlatform !== "win32") {
            child.once("spawn", () => {
                agentBrowserStarted = true;
                commitManagedSessionRestoreSuppression(managedSessionRestoreOptions);
            });
        }
        const terminateChild = (reason) => {
            if (settled)
                return;
            if (reason === "abort") {
                aborted = true;
            }
            else {
                timedOut = true;
            }
            terminateSpawnedChild(child, "SIGTERM");
            killTimer = setTimeout(() => {
                terminateSpawnedChild(child, "SIGKILL");
            }, 2_000);
        };
        const recordStdinError = (error) => {
            const stdinError = error instanceof Error ? error : new Error(String(error));
            const errorCode = stdinError.code;
            if (errorCode === "EPIPE" || errorCode === "EOF" || errorCode === "ERR_STREAM_DESTROYED") {
                return;
            }
            if (!spawnError) {
                spawnError = stdinError;
            }
        };
        const writeChildStdin = () => {
            if (aborted || signal?.aborted) {
                child.stdin.destroy();
                return;
            }
            try {
                if (stdin) {
                    child.stdin.write(stdin);
                }
                child.stdin.end();
            }
            catch (error) {
                recordStdinError(error);
                child.stdin.destroy();
            }
        };
        child.stdin.on("error", recordStdinError);
        child.once("error", (error) => {
            spawnError = error instanceof Error ? error : new Error(String(error));
            finish(resolveSpawnedChildExitCode({
                useExitFallback: false,
                timedOut,
                spawnError,
            }));
        });
        completionWatcher = watchSpawnedChildCompletion(child, {
            graceMs: EXIT_STDIO_GRACE_MS,
            onComplete: finish,
            getContext: () => ({ timedOut, spawnError }),
        });
        child.stdout.on("data", (chunk) => {
            queueStdoutChunk(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
        });
        child.stderr.on("data", (chunk) => {
            stderr = appendTail(stderr, chunk.toString(), MAX_BUFFERED_STDERR_CHARS);
        });
        if (timeoutMs > 0) {
            timeoutTimer = setTimeout(() => terminateChild("timeout"), timeoutMs);
            timeoutTimer.unref?.();
        }
        if (signal) {
            abortListener = () => terminateChild("abort");
            signal.addEventListener("abort", abortListener, { once: true });
            if (signal.aborted)
                terminateChild("abort");
        }
        writeChildStdin();
    });
}
