/**
 * Purpose: Keep the upstream agent-browser CLI from silently loading configuration the checked-out project controls.
 * Responsibilities: Resolve the upstream project/user config paths, decide when the child needs a wrapper-owned config pin, and phrase the operator opt-in plus the pin failure.
 * Scope: Pure path and opt-in policy; materializing the pinned file and building the child environment stay in process.js.
 * Invariants/Assumptions: Upstream resolves `./agent-browser.json` from the child cwd, `--config`/`AGENT_BROWSER_CONFIG` replace that discovery, and only user-owned input (an environment opt-in or a config path the user pinned themselves) lets project-scope values through.
 */
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { join, resolve } from "node:path";
/** Upstream's own spelling of `--config`; setting it makes project discovery lose. */
export const UPSTREAM_CONFIG_ENV = "AGENT_BROWSER_CONFIG";
export const UPSTREAM_PROJECT_CONFIG_FILE_NAME = "agent-browser.json";
export const UPSTREAM_PROJECT_CONFIG_TRUST_ENV = "PI_AGENT_BROWSER_TRUST_PROJECT_CONFIG";
export const UPSTREAM_USER_CONFIG_RELATIVE_PATH = /** @type {const} */ ([".agent-browser", "config.json"]);
/** An upstream config file that carries no launch settings, used when the user has no user-level config of their own. */
export const NEUTRAL_UPSTREAM_CONFIG_TEXT = "{}\n";
function isTruthyEnvValue(value) {
    const normalized = value?.trim().toLowerCase();
    return normalized === "1" || normalized === "true" || normalized === "yes";
}
/** @param {NodeJS.ProcessEnv} [env] */
export function isUpstreamProjectConfigTrusted(env = process.env) {
    return isTruthyEnvValue(env[UPSTREAM_PROJECT_CONFIG_TRUST_ENV]);
}
/** @param {NodeJS.ProcessEnv} [env] */
export function getUpstreamUserConfigPath(env = process.env) {
    const home = env.HOME?.trim() || env.USERPROFILE?.trim() || homedir();
    return join(home, ...UPSTREAM_USER_CONFIG_RELATIVE_PATH);
}
/** @param {string} cwd */
export function getUpstreamProjectConfigPath(cwd) {
    return resolve(cwd, UPSTREAM_PROJECT_CONFIG_FILE_NAME);
}
/**
 * Upstream discovers `./agent-browser.json` in its own cwd, and the wrapper spawns it in the session cwd, so a
 * checked-out project can set `executablePath`, `initScripts`, `proxy`, `allowFileAccess`, or `plugins` with no
 * wrapper flag at all - the same capabilities the privileged-flag gate protects. Pinning upstream's own
 * `AGENT_BROWSER_CONFIG` replaces that discovery, so the child keeps the user-level layer and drops the project
 * layer. The user-level layer is copied into a wrapper-owned file rather than pinned in place so nothing the child
 * does can edit the real user config as a side effect of the pin. Upstream treats a pinned config as read-only
 * (`--config <path>` loads a file) and `plugin add` writes the file its own scope names - `./agent-browser.json`, or
 * `~/.agent-browser/config.json` with `--global` - so the pin never swallows a configuration write; what the pin does
 * mean is that a plugin added to the project file only takes effect once the user trusts that file, which the
 * session-start notice below says.
 * @param {{ cwd?: string; env?: NodeJS.ProcessEnv; exists?: (path: string) => boolean }} [options]
 * @returns {{ kind: "unchanged" } | { kind: "pin"; projectConfigPath: string; userConfigPath?: string }}
 */
export function planUpstreamConfigPin(options = {}) {
    const env = options.env ?? process.env;
    const { cwd } = options;
    if (cwd === undefined)
        return { kind: "unchanged" };
    // A config path the user pinned themselves already beats project discovery, so it is left exactly as authored.
    if (env[UPSTREAM_CONFIG_ENV]?.trim())
        return { kind: "unchanged" };
    if (isUpstreamProjectConfigTrusted(env))
        return { kind: "unchanged" };
    const exists = options.exists ?? existsSync;
    const projectConfigPath = getUpstreamProjectConfigPath(cwd);
    if (!exists(projectConfigPath))
        return { kind: "unchanged" };
    const userConfigPath = getUpstreamUserConfigPath(env);
    return exists(userConfigPath) ? { kind: "pin", projectConfigPath, userConfigPath } : { kind: "pin", projectConfigPath };
}
/**
 * @param {{ projectConfigPath: string; userConfigPath?: string }} plan
 * @param {unknown} error
 */
export function getUpstreamConfigPinFailureError(plan, error) {
    const detail = (error instanceof Error ? error.message : String(error)).replace(/\.\s*$/, "");
    return [
        `Refusing to run agent-browser because the project-level ${plan.projectConfigPath} could not be kept out of the child's configuration: ${detail}.`,
        `That file can set a browser executable, page init scripts, a proxy, local-file access, or plugin commands, and the checked-out project controls it, so the wrapper pins upstream's ${UPSTREAM_CONFIG_ENV} instead of letting it be discovered.`,
        `Retry once the wrapper temp directory is writable, or have the user approve the project file by starting pi with ${UPSTREAM_PROJECT_CONFIG_TRUST_ENV}=1.`,
    ].join(" ");
}
/**
 * @param {{ projectConfigPath: string; userConfigPath?: string }} plan
 * @returns {string}
 */
export function getUpstreamProjectConfigIgnoredNotice(plan) {
    return [
        `Ignored project-level upstream config ${plan.projectConfigPath}: it can set a browser executable, page init scripts, a proxy, local-file access, or plugin commands, and the checked-out project controls it.`,
        plan.userConfigPath ? `The user-level ${plan.userConfigPath} still applies.` : `No user-level agent-browser config was found, so upstream defaults apply.`,
        `To apply the project file, have the user start pi with ${UPSTREAM_PROJECT_CONFIG_TRUST_ENV}=1.`,
    ].join(" ");
}
