/**
 * Purpose: Own the wrapper policy for raw browser/Electron launch switches that can execute host code or read local files.
 * Responsibilities: Classify code-execution and sandbox-disabling switches, publish the known-safe Electron appArgs allowlist, and read the operator opt-ins (environment variables plus user-scope config values) that widen either list.
 * Scope: Token and opt-in policy; argv assembly lives in runtime.js, Electron input compilation in input-modes/electron.js, and spawning in electron/launch.js.
 * Invariants/Assumptions: Denied switches stay denied even when an opt-in is set, and every gate keys on user-owned input (environment variables or user-scope config) rather than on repo- or model-controlled input.
 */
import { isAbsolute, resolve } from "node:path";
import { getFlagName } from "./argv-grammar.js";
import { loadAgentBrowserConfigSync } from "./config.js";
export const ELECTRON_EXTRA_APP_ARGS_ENV = "PI_AGENT_BROWSER_ELECTRON_EXTRA_APP_ARGS";
export const PRIVILEGED_ARGV_FLAGS_ENV = "PI_AGENT_BROWSER_ALLOW_PRIVILEGED_FLAGS";
export const CODE_EXECUTION_LAUNCH_FLAGS = [
    "--no-sandbox",
    "--disable-gpu-sandbox",
    "--disable-setuid-sandbox",
    "--load-extension",
    "--disable-web-security",
    "--remote-allow-origins",
    "--inspect",
    "--inspect-brk",
    "--inspect-port",
];
export const CODE_EXECUTION_LAUNCH_FLAG_PATTERNS = [/-launcher$/, /-cmd-prefix$/];
export const ELECTRON_ALLOWED_APP_ARG_FLAGS = [
    "--disable-background-timer-throttling",
    "--disable-backgrounding-occluded-windows",
    "--disable-dev-shm-usage",
    "--disable-extensions",
    "--disable-features",
    "--disable-gpu",
    "--disable-renderer-backgrounding",
    "--disable-software-rasterizer",
    "--enable-features",
    "--enable-logging",
    "--force-device-scale-factor",
    "--headless",
    "--hidden",
    "--in-process-gpu",
    "--lang",
    "--log-level",
    "--no-default-browser-check",
    "--no-first-run",
    "--ozone-platform",
    "--ozone-platform-hint",
    "--password-store",
    "--start-fullscreen",
    "--start-maximized",
    "--test-type",
    "--use-angle",
    "--use-gl",
    "--user-agent",
    "--window-position",
    "--window-size",
];
export const PRIVILEGED_ARGV_FLAGS = [
    "--allow-file-access",
    "--args",
    "--config",
    "--executable-path",
    "--extension",
    "--init-script",
    "--proxy",
];
function isTruthyOptInValue(value) {
    const normalized = value?.trim().toLowerCase();
    return normalized === "1" || normalized === "true" || normalized === "yes" || normalized === "all";
}
/**
 * Chromium accepts a single-dash spelling of every switch and lowercases switch names on Windows, so the denied
 * forms are matched against a normalized flag rather than the literal token.
 * @param {string} flag
 */
export function normalizeLaunchFlag(flag) {
    const lowercased = flag.trim().toLowerCase();
    return lowercased.startsWith("--") || !lowercased.startsWith("-") ? lowercased : `-${lowercased}`;
}
/** @param {string} flag */
export function isCodeExecutionLaunchFlag(flag) {
    const normalizedFlag = normalizeLaunchFlag(flag);
    return CODE_EXECUTION_LAUNCH_FLAGS.includes(normalizedFlag) || CODE_EXECUTION_LAUNCH_FLAG_PATTERNS.some((pattern) => pattern.test(normalizedFlag));
}
/**
 * Finds the first token that would hand a Chromium/Electron switch the ability to run a host command
 * or drop the renderer sandbox, in both `--flag=value` and separated-value spellings.
 * @param {readonly string[]} tokens
 */
export function findCodeExecutionLaunchFlag(tokens) {
    for (const token of tokens) {
        const trimmed = token.trim();
        if (!trimmed.startsWith("-"))
            continue;
        const flag = getFlagName(trimmed);
        if (isCodeExecutionLaunchFlag(flag))
            return flag;
    }
    return undefined;
}
/** @param {string} flag */
export function isAllowedElectronAppArgFlag(flag) {
    return ELECTRON_ALLOWED_APP_ARG_FLAGS.includes(flag);
}
/** @param {NodeJS.ProcessEnv} [env] */
export function isElectronExtraAppArgsAllowed(env = process.env) {
    return isTruthyOptInValue(env[ELECTRON_EXTRA_APP_ARGS_ENV]);
}
/**
 * @param {string} flag
 * @param {NodeJS.ProcessEnv} [env]
 */
export function isPrivilegedArgvFlagAllowed(flag, env = process.env) {
    const rawValue = env[PRIVILEGED_ARGV_FLAGS_ENV];
    if (isTruthyOptInValue(rawValue))
        return true;
    if (!rawValue)
        return false;
    return rawValue
        .split(/[,\s]+/)
        .map((entry) => entry.trim())
        .filter((entry) => entry.length > 0)
        .some((entry) => (entry.startsWith("-") ? entry : `--${entry}`) === flag);
}
let cachedUserScopedBrowserExecutablePath;
function loadUserScopedBrowserExecutablePath(env) {
    return loadAgentBrowserConfigSync({ env, includeProjectConfig: false }).trustedBrowserExecutablePath?.trim() || undefined;
}
/**
 * The trusted projection reads user-owned layers only (global config plus an explicit PI_AGENT_BROWSER_CONFIG
 * override), so a value the user authored there is already approved; project-scope values stay out of it.
 * @param {NodeJS.ProcessEnv} env
 */
function getUserScopedBrowserExecutablePath(env) {
    if (env !== process.env)
        return loadUserScopedBrowserExecutablePath(env);
    cachedUserScopedBrowserExecutablePath ??= loadUserScopedBrowserExecutablePath(env) ?? "";
    return cachedUserScopedBrowserExecutablePath || undefined;
}
function isSameExecutablePath(requestedValue, configuredPath) {
    const requested = requestedValue.trim();
    if (requested.length > 0 && requested === configuredPath.trim())
        return true;
    return isAbsolute(requested) && isAbsolute(configuredPath) && resolve(requested) === resolve(configuredPath);
}
/**
 * A privileged flag whose value the user authored in user scope needs no extra opt-in; a model-chosen or
 * project-scoped value still does.
 * @param {string} flag
 * @param {string | undefined} value
 * @param {NodeJS.ProcessEnv} [env]
 */
export function isPrivilegedArgvFlagValueAllowed(flag, value, env = process.env) {
    if (isPrivilegedArgvFlagAllowed(flag, env))
        return true;
    if (flag !== "--executable-path" || value === undefined)
        return false;
    const configuredPath = getUserScopedBrowserExecutablePath(env);
    return configuredPath !== undefined && isSameExecutablePath(value, configuredPath);
}
