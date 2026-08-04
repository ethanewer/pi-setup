import { extname, isAbsolute } from "node:path";
import { GLOBAL_BOOLEAN_FLAGS_WITH_OPTIONAL_VALUES, VALUE_FLAGS, getFlagName } from "../../argv-grammar.js";
const SCREENSHOT_BOOLEAN_FLAGS = new Set(["--annotate", "--full", "-f"]);
const SCREENSHOT_VALUE_FLAGS = new Set(["--screenshot-dir", "--screenshot-format", "--screenshot-quality"]);
const SCREENSHOT_IMAGE_EXTENSIONS = new Set([".jpeg", ".jpg", ".png", ".webp"]);
function isImagePathToken(token) {
    const extension = extname(token).toLowerCase();
    return SCREENSHOT_IMAGE_EXTENSIONS.has(extension);
}
export function getScreenshotPathTokenIndex(commandTokens) {
    if (commandTokens[0] !== "screenshot") {
        return undefined;
    }
    const positionalIndices = [];
    for (let index = 1; index < commandTokens.length; index += 1) {
        const token = commandTokens[index];
        if (token === "--") {
            for (let positionalIndex = index + 1; positionalIndex < commandTokens.length; positionalIndex += 1) {
                positionalIndices.push(positionalIndex);
            }
            break;
        }
        if (token.startsWith("-")) {
            const normalizedToken = token.split("=", 1)[0] ?? token;
            if ((SCREENSHOT_VALUE_FLAGS.has(normalizedToken) || VALUE_FLAGS.has(normalizedToken)) && !token.includes("=")) {
                index += 1;
                continue;
            }
            if (SCREENSHOT_BOOLEAN_FLAGS.has(normalizedToken) || GLOBAL_BOOLEAN_FLAGS_WITH_OPTIONAL_VALUES.has(normalizedToken)) {
                if (["true", "false"].includes(commandTokens[index + 1] ?? ""))
                    index += 1;
                continue;
            }
        }
        positionalIndices.push(index);
    }
    if (positionalIndices.length === 0) {
        return undefined;
    }
    const candidateIndex = positionalIndices[positionalIndices.length - 1];
    const candidate = commandTokens[candidateIndex];
    if (positionalIndices.length >= 2 || isImagePathToken(candidate) || isAbsolute(candidate) || candidate.startsWith("./") || candidate.startsWith("../")) {
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
