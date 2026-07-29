/**
 * Purpose: Execute the upstream agent-browser binary for the pi-agent-browser extension.
 * Responsibilities: Spawn the pinned agent-browser subprocess in its own POSIX process group, forward vetted parent environment variables plus wrapper overrides, stream optional stdin, bound in-memory output buffering, spill oversized stdout safely to a private temp file under a disk budget, and honor abort signals plus the parent's interrupt.
 * Scope: Process execution only; argument planning, output formatting, and pi tool registration live elsewhere.
 * Usage: Called by the extension tool after argument validation and session planning are complete.
 * Invariants/Assumptions: The binary is the `agent-browser` file resolved by child-process-policy; Windows routes through PowerShell to invoke npm launchers with escaped argv; callers handle semantic success/error interpretation.
 */
import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { chmod, mkdir, readFile, stat } from "node:fs/promises";
import { constants as osConstants } from "node:os";
import { env as processEnv, platform as processPlatform } from "node:process";
import { GLOBAL_BOOLEAN_FLAGS_WITH_OPTIONAL_VALUES, GLOBAL_VALUE_FLAGS, getFlagName } from "./argv-grammar.js";
import { DENIED_CHILD_ENV_VARS, isFullChildEnvForwardingAllowed, resolveAgentBrowserCliPath, sanitizeChildPathValue, } from "./child-process-policy.js";
import { getImplicitSessionIdleTimeoutMs } from "./runtime.js";
import { openSecureTempFile, writeSecureTempChunk, writeSecureTempFile } from "./temp.js";
import { NEUTRAL_UPSTREAM_CONFIG_TEXT, UPSTREAM_CONFIG_ENV, getUpstreamConfigPinFailureError, planUpstreamConfigPin, } from "./upstream-config-policy.js";
const MAX_BUFFERED_STDOUT_BYTES = 512 * 1_024;
const MAX_BUFFERED_STDERR_CHARS = 32_000;
const MAX_BUFFERED_STDOUT_TAIL_CHARS = 32_000;
const PROCESS_STDOUT_SPILL_FILE_PREFIX = "process-stdout";
const UPSTREAM_CONFIG_PIN_FILE_PREFIX = "upstream-config";
const AGENT_BROWSER_SOCKET_DIR_ENV = "AGENT_BROWSER_SOCKET_DIR";
const AGENT_BROWSER_DEFAULT_TIMEOUT_ENV = "AGENT_BROWSER_DEFAULT_TIMEOUT";
const AGENT_BROWSER_IDLE_TIMEOUT_ENV = "AGENT_BROWSER_IDLE_TIMEOUT_MS";
const PI_AGENT_BROWSER_PROCESS_TIMEOUT_ENV = "PI_AGENT_BROWSER_PROCESS_TIMEOUT_MS";
const DEFAULT_AGENT_BROWSER_SOCKET_DIR_PREFIX = "/tmp/piab";
export const SAFE_AGENT_BROWSER_OPERATION_TIMEOUT_MS = 25_000;
const DEFAULT_AGENT_BROWSER_PROCESS_TIMEOUT_MS = 35_000;
/** Grace period after `exit` before resolving when `close` is delayed by inherited stdio handles. */
const EXIT_STDIO_GRACE_MS = 100;
/** Grace period after SIGTERM before the process group is escalated to SIGKILL. */
const CHILD_TERMINATION_ESCALATION_MS = 2_000;
/** Poll step used to hand a parent interrupt back as soon as the terminated children are actually gone. */
const PARENT_INTERRUPT_SETTLE_POLL_MS = 50;
function appendTail(text, addition, maxChars) {
    const combined = text + addition;
    return combined.length <= maxChars ? combined : combined.slice(combined.length - maxChars);
}
function quoteWindowsPowerShellArg(value) {
    return `'${value.replace(/'/g, "''")}'`;
}
const WINDOWS_LEADING_GLOBAL_VALUE_FLAGS = new Set(GLOBAL_VALUE_FLAGS);
/** Exported for unit tests that lock Windows launcher argv ordering. */
export function reorderWindowsLeadingGlobalArgs(args) {
    const leadingGlobals = [];
    let index = 0;
    while (index < args.length && args[index]?.startsWith("-")) {
        const token = args[index];
        const flagName = getFlagName(token);
        leadingGlobals.push(token);
        index += 1;
        if (WINDOWS_LEADING_GLOBAL_VALUE_FLAGS.has(flagName) && !token.includes("=") && index < args.length) {
            leadingGlobals.push(args[index]);
            index += 1;
            continue;
        }
        if (GLOBAL_BOOLEAN_FLAGS_WITH_OPTIONAL_VALUES.has(flagName) && ["true", "false"].includes(args[index] ?? "")) {
            leadingGlobals.push(args[index]);
            index += 1;
        }
    }
    if (leadingGlobals.length === 0 || index >= args.length)
        return args;
    return [args[index], ...leadingGlobals, ...args.slice(index + 1)];
}
export function buildAgentBrowserSpawnCommand(args, platform = processPlatform, options = {}) {
    const resolvedCli = resolveAgentBrowserCliPath({ cwd: options.cwd, env: options.env, platform });
    if (platform !== "win32") {
        return { command: resolvedCli.path ?? "agent-browser", args, error: resolvedCli.error };
    }
    const launcher = resolvedCli.path ? quoteWindowsPowerShellArg(resolvedCli.path) : "agent-browser.cmd";
    const commandLine = ["&", launcher, ...reorderWindowsLeadingGlobalArgs(args).map(quoteWindowsPowerShellArg)].join(" ");
    return { command: "powershell.exe", args: ["-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", commandLine], error: resolvedCli.error };
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
/**
 * The POSIX child leads its own process group, so a terminal Ctrl-C no longer reaches it; the parent's interrupt is
 * forwarded to the same termination path the abort signal uses. Node suppresses its default SIGINT exit while a
 * listener is attached, so the interrupt is re-raised once the host has no handler of its own.
 */
const activeChildTerminators = new Set();
const interruptEscalationChildren = new Set();
let parentInterruptListener;
/**
 * Evaluated at signal time instead of cached when the wrapper's listener is attached, because the host may attach
 * its own SIGINT handler later; the wrapper's own listener never counts as the host's.
 */
function hostHandlesParentInterrupt() {
    return process.listeners("SIGINT").some((listener) => listener !== parentInterruptListener);
}
/**
 * Re-raising SIGINT ends this process through the default disposition, and a signal death runs neither pending
 * timers nor `exit` handlers, so anything still alive is escalated to SIGKILL here rather than by a timer that the
 * parent's own death would cancel.
 */
function raiseParentInterrupt() {
    // Includes any run started after the interrupt: this process is about to die, so its children cannot be left behind.
    for (const child of new Set([...interruptEscalationChildren, ...activeChildTerminators])) {
        if (child.isRunning())
            child.escalate();
    }
    interruptEscalationChildren.clear();
    activeChildTerminators.clear();
    detachParentInterruptListener();
    process.kill(process.pid, "SIGINT");
}
/** Hands the interrupt back as soon as the interrupted children are gone, and at the escalation deadline otherwise. */
function escalateInterruptedChildren(interruptedChildren) {
    for (const child of interruptedChildren) {
        if (child.isRunning())
            interruptEscalationChildren.add(child);
    }
    if (interruptEscalationChildren.size === 0) {
        raiseParentInterrupt();
        return;
    }
    let settleTimer;
    const escalationTimer = setTimeout(() => {
        clearInterval(settleTimer);
        raiseParentInterrupt();
    }, CHILD_TERMINATION_ESCALATION_MS);
    settleTimer = setInterval(() => {
        if ([...interruptEscalationChildren].some((child) => child.isRunning()))
            return;
        clearInterval(settleTimer);
        clearTimeout(escalationTimer);
        raiseParentInterrupt();
    }, PARENT_INTERRUPT_SETTLE_POLL_MS);
}
function handleParentInterrupt() {
    const interruptedChildren = [...activeChildTerminators];
    for (const child of interruptedChildren) {
        child.terminate();
    }
    if (hostHandlesParentInterrupt())
        return;
    activeChildTerminators.clear();
    escalateInterruptedChildren(interruptedChildren);
}
function detachParentInterruptListener() {
    if (!parentInterruptListener)
        return;
    process.removeListener("SIGINT", parentInterruptListener);
    parentInterruptListener = undefined;
}
function addParentInterruptTerminator(childTerminator) {
    activeChildTerminators.add(childTerminator);
    if (parentInterruptListener)
        return;
    parentInterruptListener = handleParentInterrupt;
    process.on("SIGINT", parentInterruptListener);
}
function removeParentInterruptTerminator(childTerminator) {
    activeChildTerminators.delete(childTerminator);
    interruptEscalationChildren.delete(childTerminator);
    if (activeChildTerminators.size === 0 && interruptEscalationChildren.size === 0)
        detachParentInterruptListener();
}
function getSignalTerminationExitCode(signal) {
    const signalNumber = osConstants.signals[signal];
    return typeof signalNumber === "number" ? 128 + signalNumber : 128;
}
/** Exported for unit tests that lock subprocess exit-code precedence. */
export function resolveSpawnedChildExitCode(input) {
    // Precedence: observed `close` code when present, then wrapper timeout (124), then
    // post-`exit` fallback when inherited stdio delays `close`, then signal death (128+n),
    // then spawn failure (127).
    if (input.closeCode !== null && input.closeCode !== undefined) {
        return input.closeCode;
    }
    if (input.timedOut) {
        return 124;
    }
    if (input.useExitFallback && input.exitCode !== null && input.exitCode !== undefined) {
        return input.exitCode;
    }
    const terminationSignal = input.closeSignal ?? input.exitSignal;
    if (terminationSignal) {
        return getSignalTerminationExitCode(terminationSignal);
    }
    return input.spawnError ? 127 : 0;
}
function watchSpawnedChildCompletion(child, options) {
    let exited = false;
    let exitCode = null;
    let exitSignal = null;
    let postExitTimer;
    // `completed` suppresses duplicate exit/close callbacks; `settled` in `finish` guards async spill cleanup.
    let completed = false;
    const complete = (closeCode, closeSignal) => {
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
            closeSignal,
            exitCode,
            exitSignal,
            useExitFallback: exited,
            timedOut: context.timedOut,
            spawnError: context.spawnError,
        }));
    };
    child.once("exit", (code, signal) => {
        exited = true;
        exitCode = code;
        exitSignal = signal;
        postExitTimer = setTimeout(() => {
            destroySpawnedChildStreams(child);
            complete(undefined, undefined);
        }, options.graceMs);
        postExitTimer.unref?.();
    });
    child.once("close", (code, signal) => {
        complete(code, signal);
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
export function getAgentBrowserSocketDir(platform = processPlatform, uid = typeof process.getuid === "function" ? process.getuid() : undefined) {
    if (platform === "win32") {
        return undefined;
    }
    return `${DEFAULT_AGENT_BROWSER_SOCKET_DIR_PREFIX}${typeof uid === "number" ? `-${uid}` : ""}`;
}
/**
 * The pinned file is a wrapper-owned copy of the user-level upstream config, so the user's own defaults keep
 * applying while project discovery loses, and the pin cannot edit the real user config; a command that would write
 * configuration is refused rather than writing the copy. It is cached per source file identity and re-created when
 * session cleanup removed it.
 */
let pinnedUpstreamConfigFile;
async function readUpstreamConfigPinSource(userConfigPath) {
    if (userConfigPath === undefined) {
        return { key: "neutral", text: NEUTRAL_UPSTREAM_CONFIG_TEXT };
    }
    const stats = await stat(userConfigPath).catch(() => undefined);
    if (!stats?.isFile()) {
        return { key: "neutral", text: NEUTRAL_UPSTREAM_CONFIG_TEXT };
    }
    return { key: `${userConfigPath}:${stats.mtimeMs}:${stats.size}`, text: await readFile(userConfigPath, "utf8") };
}
async function ensureUpstreamConfigPinPath(userConfigPath) {
    const source = await readUpstreamConfigPinSource(userConfigPath);
    if (pinnedUpstreamConfigFile?.key === source.key && existsSync(pinnedUpstreamConfigFile.path)) {
        return pinnedUpstreamConfigFile.path;
    }
    const path = await writeSecureTempFile({
        content: source.text,
        prefix: UPSTREAM_CONFIG_PIN_FILE_PREFIX,
        suffix: ".json",
    });
    pinnedUpstreamConfigFile = { key: source.key, path };
    return path;
}
async function ensureAgentBrowserSocketDir(socketDir) {
    try {
        await mkdir(socketDir, { recursive: true, mode: 0o700 });
        await chmod(socketDir, 0o700).catch(() => undefined);
        return true;
    }
    catch {
        return false;
    }
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
export async function runAgentBrowserProcess(options) {
    const { args, cwd, env, signal, stdin } = options;
    const timeoutMs = options.timeoutMs ?? getAgentBrowserProcessTimeoutMs();
    const processOverrides = {
        [AGENT_BROWSER_IDLE_TIMEOUT_ENV]: String(getImplicitSessionIdleTimeoutMs()),
        ...env,
    };
    const explicitSocketDir = processOverrides[AGENT_BROWSER_SOCKET_DIR_ENV];
    let effectiveEnv = explicitSocketDir === undefined ? { ...processOverrides, [AGENT_BROWSER_SOCKET_DIR_ENV]: undefined } : processOverrides;
    const requestedSocketDir = explicitSocketDir ?? getAgentBrowserSocketDir();
    if (requestedSocketDir && (await ensureAgentBrowserSocketDir(requestedSocketDir))) {
        effectiveEnv = { ...effectiveEnv, [AGENT_BROWSER_SOCKET_DIR_ENV]: requestedSocketDir };
    }
    // Upstream discovers `./agent-browser.json` in the child cwd, so an untrusted project file is replaced by a
    // wrapper-owned pin before the child can read it; an unavailable pin fails the run instead of letting it apply.
    // `spawn` runs the child in this process's cwd when none is given, so that is the directory upstream discovers in.
    const upstreamConfigPin = planUpstreamConfigPin({ cwd: cwd ?? process.cwd(), env: processEnv });
    if (upstreamConfigPin.kind === "pin") {
        let pinnedConfigPath;
        try {
            pinnedConfigPath = await ensureUpstreamConfigPinPath(upstreamConfigPin.userConfigPath);
        }
        catch (error) {
            return {
                aborted: false,
                exitCode: 127,
                spawnError: new Error(getUpstreamConfigPinFailureError(upstreamConfigPin, error)),
                stderr: "",
                stdout: "",
                timedOut: false,
            };
        }
        effectiveEnv = { ...effectiveEnv, [UPSTREAM_CONFIG_ENV]: pinnedConfigPath };
    }
    const childEnv = buildAgentBrowserProcessEnv(processEnv, effectiveEnv, { cwd });
    // Resolution reads the unscrubbed parent PATH so a workspace-local shim is reported instead of silently missing.
    const spawnCommand = buildAgentBrowserSpawnCommand(args, processPlatform, { cwd, env: processEnv });
    if (spawnCommand.error) {
        return {
            aborted: false,
            exitCode: 127,
            spawnError: new Error(spawnCommand.error),
            stderr: "",
            stdout: "",
            timedOut: false,
        };
    }
    return await new Promise((resolve) => {
        let aborted = false;
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
        let parentInterruptTerminator;
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
            if (parentInterruptTerminator) {
                removeParentInterruptTerminator(parentInterruptTerminator);
                parentInterruptTerminator = undefined;
            }
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
                if (!spawnError && stdoutSpillError) {
                    spawnError = stdoutSpillError;
                }
                // Idempotent teardown: streams may already be destroyed by the post-`exit` fallback.
                destroySpawnedChildStreams(child);
                resolve({
                    aborted,
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
        const child = spawn(spawnCommand.command, spawnCommand.args, {
            cwd,
            // Own process group on POSIX so timeout/abort termination reaches upstream descendants.
            detached: processPlatform !== "win32",
            env: childEnv,
            stdio: ["pipe", "pipe", "pipe"],
        });
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
            }, CHILD_TERMINATION_ESCALATION_MS);
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
        parentInterruptTerminator = {
            escalate: () => terminateSpawnedChild(child, "SIGKILL"),
            isRunning: () => child.exitCode === null && child.signalCode === null,
            terminate: () => terminateChild("abort"),
        };
        addParentInterruptTerminator(parentInterruptTerminator);
        if (signal) {
            if (signal.aborted) {
                terminateChild("abort");
            }
            else {
                abortListener = () => terminateChild("abort");
                signal.addEventListener("abort", abortListener, { once: true });
            }
        }
        writeChildStdin();
    });
}
