import { lstatSync, readlinkSync, realpathSync, statSync } from "node:fs";
import { basename, dirname, join, resolve } from "node:path";
import { foldAgentBrowserFilesystemIdentity, getFlagName } from "../../argv-grammar.js";
import { parseWaitCommandTokens } from "../../argv-descriptor.js";
const SCREENSHOT_BOOLEAN_FLAGS = new Set(["--annotate", "--full", "-f"]);
const SCREENSHOT_VALUE_FLAGS = new Set(["--screenshot-dir", "--screenshot-format", "--screenshot-quality"]);
const SCREENSHOT_IMAGE_EXTENSIONS = [".jpeg", ".jpg", ".png", ".webp"];
function isSingleScreenshotPathToken(token) {
    const explicitlyRelative = token.startsWith("./") || token.startsWith("../");
    if (token.startsWith("#") || token.startsWith("@") || (token.startsWith(".") && !explicitlyRelative && !token.includes("/")))
        return false;
    return explicitlyRelative || token.includes("/") || SCREENSHOT_IMAGE_EXTENSIONS.some((extension) => token.endsWith(extension));
}
function getScreenshotPositionalIndices(commandTokens) {
    if (commandTokens[0] !== "screenshot")
        return [];
    const positionalIndices = [];
    for (let index = 1; index < commandTokens.length; index += 1) {
        const token = commandTokens[index];
        if (SCREENSHOT_VALUE_FLAGS.has(token)) {
            index += 1;
            continue;
        }
        if (SCREENSHOT_BOOLEAN_FLAGS.has(token))
            continue;
        positionalIndices.push(index);
    }
    return positionalIndices;
}
export function getScreenshotPathTokenIndex(commandTokens) {
    const positionalIndices = getScreenshotPositionalIndices(commandTokens);
    if (positionalIndices.length === 0)
        return undefined;
    const candidateIndex = positionalIndices.length >= 2 ? positionalIndices[1] : positionalIndices[0];
    const candidate = commandTokens[candidateIndex];
    if (positionalIndices.length >= 2 || isSingleScreenshotPathToken(candidate)) {
        return candidateIndex;
    }
    return undefined;
}
/**
 * The remaining upstream commands that write a file the caller names. `download`, `pdf`, `state save`,
 * `wait --download`, and `screenshot` are read by the token readers above, so without these a trace, profile,
 * recording, HAR capture, or diff image path never reaches the write-path guards.
 */
const POSITIONAL_ARTIFACT_PATH_COMMAND_PREFIXES = [
    ["network", "har", "stop"],
    ["profiler", "start"],
    ["profiler", "stop"],
    ["record", "restart"],
    ["record", "start"],
    ["trace", "stop"],
];
/** Value flags whose value is the file the command writes. */
const ARTIFACT_PATH_VALUE_FLAGS = [{ command: "diff", flag: "--output" }];
function matchesCommandPrefix(commandTokens, prefix) {
    return prefix.every((token, index) => commandTokens[index] === token);
}
/** Only the first positional after the subcommand is the artifact path, so `record start <path> [url]` keeps its URL out. */
function getFirstPositionalTokenAfter(commandTokens, startIndex) {
    let positionalOnly = false;
    for (let index = startIndex; index < commandTokens.length; index += 1) {
        const token = commandTokens[index];
        if (!positionalOnly && token === "--") {
            positionalOnly = true;
            continue;
        }
        if (positionalOnly || !token.startsWith("-"))
            return token;
        if (VALUE_FLAGS.has(getFlagName(token)) && !token.includes("="))
            index += 1;
    }
    return undefined;
}
/**
 * Requested artifact paths of the trace, profile, recording, HAR, and diff-image commands, as written by the caller.
 * @param {readonly string[]} commandTokens
 * @returns {string[]}
 */
export function getDiagnosticArtifactWritePaths(commandTokens) {
    const requestedPaths = [];
    for (const prefix of POSITIONAL_ARTIFACT_PATH_COMMAND_PREFIXES) {
        if (!matchesCommandPrefix(commandTokens, prefix))
            continue;
        const requestedPath = getFirstPositionalTokenAfter(commandTokens, prefix.length);
        if (requestedPath !== undefined)
            requestedPaths.push(requestedPath);
    }
    for (const { command, flag } of ARTIFACT_PATH_VALUE_FLAGS) {
        if (commandTokens[0] !== command)
            continue;
        for (const [index, token] of commandTokens.entries()) {
            if (getFlagName(token) !== flag)
                continue;
            const value = token.includes("=") ? token.slice(token.indexOf("=") + 1) : commandTokens[index + 1];
            if (value !== undefined && value.length > 0 && !value.startsWith("-"))
                requestedPaths.push(value);
        }
    }
    return requestedPaths.filter((requestedPath) => requestedPath.length > 0);
}
const DIFF_SCREENSHOT_VALUE_FLAGS = new Set(["-b", "--baseline", "-o", "--output", "-s", "--selector", "-t", "--threshold"]);
function getDiffScreenshotOutputPath(commandTokens) {
    let outputPath;
    for (let index = 2; index < commandTokens.length; index += 1) {
        const token = commandTokens[index];
        if (!DIFF_SCREENSHOT_VALUE_FLAGS.has(token))
            continue;
        const value = commandTokens[index + 1];
        if (value === undefined)
            return undefined;
        if (token === "-o" || token === "--output")
            outputPath = value;
        index += 1;
    }
    return outputPath;
}
function foldArtifactPath(path, platform) {
    return foldAgentBrowserFilesystemIdentity(path, platform);
}
function canonicalizeArtifactPath(absolutePath, platform, seenSymlinks) {
    let cursor = absolutePath;
    const suffix = [];
    while (true) {
        try {
            const canonicalPath = join(realpathSync.native(cursor), ...suffix);
            try {
                const stats = statSync(canonicalPath, { bigint: true });
                if (stats.ino > 0n)
                    return `inode:${stats.dev}:${stats.ino}`;
            }
            catch {
                // The destination does not exist yet; canonical ancestry still catches aliases.
            }
            return foldArtifactPath(canonicalPath, platform);
        }
        catch {
            let symlinkTarget;
            try {
                if (lstatSync(cursor).isSymbolicLink())
                    symlinkTarget = resolve(dirname(cursor), readlinkSync(cursor));
            }
            catch { }
            if (symlinkTarget) {
                if (seenSymlinks.has(cursor))
                    throw new Error(`Artifact destination contains a symlink loop: ${absolutePath}`);
                if (seenSymlinks.size >= 32)
                    throw new Error(`Artifact destination has too many symlink hops: ${absolutePath}`);
                seenSymlinks.add(cursor);
                return canonicalizeArtifactPath(join(symlinkTarget, ...suffix), platform, seenSymlinks);
            }
            const parent = dirname(cursor);
            if (parent === cursor)
                return foldArtifactPath(absolutePath, platform);
            suffix.unshift(basename(cursor));
            cursor = parent;
        }
    }
}
export function canonicalizeExplicitArtifactDestination(cwd, destination, platform = process.platform) {
    return canonicalizeArtifactPath(resolve(cwd, destination), platform, new Set());
}
export function getExplicitArtifactDestination(commandTokens) {
    const command = commandTokens[0];
    const subcommand = commandTokens[1];
    if (command === "screenshot") {
        const index = getScreenshotPathTokenIndex(commandTokens);
        return index === undefined ? undefined : commandTokens[index];
    }
    if (command === "download")
        return commandTokens[2];
    if (command === "pdf")
        return commandTokens[1];
    if (command === "wait")
        return parseWaitCommandTokens(commandTokens).downloadPath;
    if (command === "state" && subcommand === "save")
        return commandTokens[2];
    if (command === "diff" && subcommand === "screenshot")
        return getDiffScreenshotOutputPath(commandTokens);
    if (command === "network" && subcommand === "har" && commandTokens[2] === "stop")
        return commandTokens[3];
    if ((command === "trace" || command === "profiler") && subcommand === "stop")
        return commandTokens[2];
    if (command === "record" && (subcommand === "start" || subcommand === "restart"))
        return commandTokens[2];
    return undefined;
}
