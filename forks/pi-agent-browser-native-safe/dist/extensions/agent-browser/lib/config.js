/**
 * Purpose: Load pi-agent-browser-native package configuration from Pi-scoped global, project, or explicit paths.
 * Responsibilities: Resolve config layers, resolve secrets without exposing values, and provide redacted status for tools/CLIs.
 * Scope: Package-owned configuration only; canonical config policy lives in config-policy.js, browser command execution and web-search API calls live in focused modules.
 * Invariants/Assumptions: Credential sources from loaded config are passed through to the runtime; command credentials are resolved lazily at execution time and displayed values stay redacted.
 */
import { execFile as execFileCallback } from "node:child_process";
import { readFile } from "node:fs/promises";
import { promisify } from "node:util";
import { SECRET_COMMAND_TIMEOUT_MS, buildAgentBrowserConfigState, getAgentBrowserConfigPaths, getWebSearchCredentialSource, getWebSearchProviderOrder, isProjectCredentialCommandAllowed, loadAgentBrowserConfigStateSync, mergeAgentBrowserConfig, parseAgentBrowserConfigLayer, resolveEnvInterpolations, } from "./config-policy.js";
export { AGENT_BROWSER_CONFIG_ENV, BRAVE_API_KEY_ENV, CONFIG_RELATIVE_PATH, DEFAULT_WEB_SEARCH_PROVIDER, EXA_API_KEY_ENV, GLOBAL_CONFIG_RELATIVE_PATH, PROJECT_CREDENTIAL_COMMANDS_ENV, SECRET_COMMAND_TIMEOUT_MS, WEB_SEARCH_PROVIDER_CONFIG_KEYS, WEB_SEARCH_PROVIDER_DESCRIPTORS, WEB_SEARCH_PROVIDER_ENV_VARS, WEB_SEARCH_PROVIDERS, buildAgentBrowserConfigState, buildWebSearchCredentialSources, canRegisterWebSearchTool, classifyCredentialSource, formatBrowserExecutableStatus, formatBrowserProfileStatus, getAgentBrowserConfigPaths, getCredentialSourceSummary, getGlobalAgentBrowserConfigPath, getProjectAgentBrowserConfigPath, getWebSearchCredentialSource, getWebSearchProviderConfigKey, getWebSearchProviderDescriptor, getWebSearchProviderEnvVar, getWebSearchProviderLabel, getWebSearchProviderOrder, hasPotentialCredentialSource, isPlaintextCredentialValue, isProjectCredentialCommandAllowed, isProjectSafeCredentialValueForProvider, isWebSearchProvider, loadAgentBrowserConfigStateSync, mergeAgentBrowserConfig, parseAgentBrowserConfigLayer, resolveEnvInterpolations, summarizeConfigFiles, validateAgentBrowserConfig, validateWebSearchProvider, } from "./config-policy.js";
const execFile = promisify(execFileCallback);
const CREDENTIAL_COMMAND_CONFIG_HINT = "Check pi-agent-browser-config web-search status and the configured secret manager command.";
const CREDENTIAL_COMMAND_SHELL_EXAMPLE = '`!/bin/sh -c "pass show key | head -1"`';
const CREDENTIAL_COMMAND_ARGV_EXAMPLE = '`!["/bin/sh", "-c", "pass show key | head -1"]`';
const CREDENTIAL_COMMAND_HOME_PATH_EXAMPLE = "`!/bin/cat /Users/you/.secrets/key`";
/** Characters a shell would act on, split by whether double quotes still expand them. */
const SHELL_OPERATOR_CHARACTERS = "|&;<>()\n";
const SHELL_EXPANSION_CHARACTERS = "$`";
// Credential commands run without a shell, so quoting is honored but operators are not; a pipeline must be
// written explicitly, for example `!/bin/sh -c "pass show key | head -1"`.
// Only syntax a shell would have consumed before the executable ran is reported: an operator or expansion (which
// would otherwise resolve to a wrong credential that looks successful) and a leading `~` (which never names the home
// directory here). Filename patterns (`*`, `?`, `[`) are left alone because `execFile` hands them to the executable
// exactly as written, so the command either uses them literally as intended or fails loudly on its own.
function parseCommandArgv(command) {
    const argv = [];
    let current = "";
    let quote;
    let quoted = false;
    let shellCharacter;
    let tildeToken;
    let leadingTilde = false;
    const pushCurrentToken = () => {
        if (leadingTilde)
            tildeToken ??= current;
        argv.push(current);
        current = "";
        quoted = false;
        leadingTilde = false;
    };
    for (let index = 0; index < command.length; index += 1) {
        const char = command[index];
        if (quote) {
            if (char === quote) {
                quote = undefined;
                continue;
            }
            if (quote === '"' && char === "\\" && index + 1 < command.length) {
                current += command[index + 1];
                index += 1;
                continue;
            }
            if (quote === '"' && SHELL_EXPANSION_CHARACTERS.includes(char)) {
                shellCharacter ??= char;
            }
            current += char;
            continue;
        }
        if (char === '"' || char === "'") {
            quote = char;
            quoted = true;
            continue;
        }
        if (SHELL_OPERATOR_CHARACTERS.includes(char) || SHELL_EXPANSION_CHARACTERS.includes(char)) {
            shellCharacter ??= char;
        }
        // A shell expands a leading `~` to the home directory only at the start of an unquoted token.
        if (char === "~" && current.length === 0 && !quoted) {
            leadingTilde = true;
        }
        if (char === "\\" && index + 1 < command.length) {
            current += command[index + 1];
            index += 1;
            continue;
        }
        if (/\s/.test(char)) {
            if (current.length > 0 || quoted) {
                pushCurrentToken();
            }
            continue;
        }
        current += char;
    }
    if (quote)
        return undefined;
    if (current.length > 0 || quoted)
        pushCurrentToken();
    return argv.length > 0 ? { argv, shellCharacter, tildeToken } : undefined;
}
/** Documented escape hatch: an explicit argv array runs exactly as written, so a shell can be named on purpose. */
function parseCommandArgvArray(command) {
    let parsed;
    try {
        parsed = JSON.parse(command);
    }
    catch {
        return undefined;
    }
    if (!Array.isArray(parsed) || parsed.length === 0)
        return undefined;
    return parsed.every((entry) => typeof entry === "string" && entry.length > 0) ? parsed : undefined;
}
function parseCredentialCommandArgv(command) {
    if (command.startsWith("[")) {
        const argvArray = parseCommandArgvArray(command);
        if (!argvArray) {
            throw new Error(`Credential command starts with "[" but is not a JSON array of non-empty strings such as ${CREDENTIAL_COMMAND_ARGV_EXAMPLE}. ${CREDENTIAL_COMMAND_CONFIG_HINT}`);
        }
        return argvArray;
    }
    const parsed = parseCommandArgv(command);
    if (!parsed) {
        throw new Error(`Credential command could not be parsed into an executable and arguments. ${CREDENTIAL_COMMAND_CONFIG_HINT}`);
    }
    if (parsed.shellCharacter !== undefined) {
        throw new Error([
            `Credential command uses the shell character ${JSON.stringify(parsed.shellCharacter)}, but agent_browser runs credential commands without a shell, so pipes, redirection, command substitution, and variable expansion would be passed to the executable as literal text instead of being interpreted.`,
            `Name the shell explicitly, for example ${CREDENTIAL_COMMAND_SHELL_EXAMPLE}, or pass an exact argv array, for example ${CREDENTIAL_COMMAND_ARGV_EXAMPLE}.`,
            `Single-quote an argument that must contain the character literally.`,
            CREDENTIAL_COMMAND_CONFIG_HINT,
        ].join(" "));
    }
    if (parsed.tildeToken !== undefined) {
        throw new Error([
            `Credential command argument ${JSON.stringify(parsed.tildeToken)} starts with "~", but agent_browser runs credential commands without a shell, so the tilde is passed to the executable as a literal path segment instead of expanding to the home directory, and the command fails to find the file.`,
            `Write the path in full, for example ${CREDENTIAL_COMMAND_HOME_PATH_EXAMPLE}, or name the shell explicitly, for example ${CREDENTIAL_COMMAND_SHELL_EXAMPLE}.`,
            CREDENTIAL_COMMAND_CONFIG_HINT,
        ].join(" "));
    }
    return parsed.argv;
}
async function readConfigLayer(path, scope, errors, warnings) {
    let raw;
    try {
        raw = await readFile(path, "utf8");
    }
    catch (error) {
        if (error && typeof error === "object" && "code" in error && error.code === "ENOENT") {
            return undefined;
        }
        errors.push(`Could not read ${scope} config ${path}: ${error instanceof Error ? error.message : String(error)}`);
        return undefined;
    }
    return parseAgentBrowserConfigLayer(raw, path, scope, errors, warnings);
}
export async function loadAgentBrowserConfig(options = {}) {
    const env = options.env ?? process.env;
    const paths = getAgentBrowserConfigPaths({ cwd: options.cwd, env });
    const includeProjectConfig = options.includeProjectConfig !== false;
    const errors = [];
    const warnings = [];
    const layerCandidates = [
        { path: paths.global, scope: "global" },
        ...(includeProjectConfig ? [{ path: paths.project, scope: "project" }] : []),
        ...(paths.override ? [{ path: paths.override, scope: "override" }] : []),
    ];
    const layers = [];
    let mergedConfig = {};
    for (const candidate of layerCandidates) {
        const layer = await readConfigLayer(candidate.path, candidate.scope, errors, warnings);
        if (!layer)
            continue;
        layers.push(layer);
        mergedConfig = mergeAgentBrowserConfig(mergedConfig, layer.config);
    }
    return buildAgentBrowserConfigState({
        env,
        errors,
        layers,
        mergedConfig,
        paths,
        projectConfigIncluded: includeProjectConfig,
        warnings,
    });
}
export function loadAgentBrowserConfigSync(options = {}) {
    return loadAgentBrowserConfigStateSync(options);
}
async function resolveCommandCredential(rawValue, signal) {
    const command = rawValue.slice(1).trim();
    if (!command)
        return undefined;
    const argv = parseCredentialCommandArgv(command);
    try {
        const result = await execFile(argv[0], argv.slice(1), {
            signal,
            timeout: SECRET_COMMAND_TIMEOUT_MS,
            maxBuffer: 1024 * 1024,
        });
        const value = result.stdout.trim();
        return value.length > 0 ? value : undefined;
    }
    catch (error) {
        if (signal?.aborted)
            throw error;
        throw new Error("Credential command failed without exposing command output. Check pi-agent-browser-config web-search status and the configured secret manager command.");
    }
}
export async function resolveCredentialSource(source, options = {}) {
    if (!source)
        return undefined;
    let value;
    if (source.kind === "command") {
        if (source.scope === "project" && !isProjectCredentialCommandAllowed(options.env ?? process.env))
            return undefined;
        value = await resolveCommandCredential(source.rawValue, options.signal);
    }
    else if (source.kind === "env") {
        value = resolveEnvInterpolations(source.rawValue, options.env ?? process.env)?.trim();
    }
    else {
        value = source.rawValue.trim();
    }
    return value ? { source, value } : undefined;
}
export async function resolveWebSearchCredential(state, provider, options = {}) {
    if (!state.webSearchEnabled || state.errors.length > 0)
        return undefined;
    return resolveCredentialSource(getWebSearchCredentialSource(state, provider), options);
}
export async function resolvePreferredWebSearchCredential(state, options = {}) {
    if (!state.webSearchEnabled || state.errors.length > 0)
        return undefined;
    for (const provider of getWebSearchProviderOrder(state, options.provider)) {
        const credential = await resolveWebSearchCredential(state, provider, options);
        if (credential)
            return { provider, credential };
    }
    return undefined;
}
