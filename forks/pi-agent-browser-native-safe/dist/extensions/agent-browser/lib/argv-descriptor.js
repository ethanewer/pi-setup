/**
 * Purpose: Parse raw agent-browser argv once into a stable command descriptor for planners and policy.
 * Responsibilities: Own command-token extraction, command/subcommand identification, and descriptor construction.
 * Scope: Pure argv parsing; runtime planning and session policy consume descriptors instead of re-parsing tokens.
 */
import { GLOBAL_BOOLEAN_FLAGS_WITH_OPTIONAL_VALUES, VALUE_FLAGS, optionalGlobalValueFlagConsumesNext } from "./argv-grammar.js";
import { isOpenNavigationCommand } from "./command-taxonomy.js";
function isBooleanLiteral(token) {
    const normalized = token?.trim().toLowerCase();
    return normalized === "true" || normalized === "false";
}
export function findCommandStartIndex(args) {
    for (let index = 0; index < args.length; index += 1) {
        const token = args[index];
        if (token.startsWith("--session=") || token.startsWith("--namespace=") || token.startsWith("--restore=")) {
            continue;
        }
        if (token.startsWith("-")) {
            const normalizedToken = token.split("=", 1)[0] ?? token;
            if (optionalGlobalValueFlagConsumesNext(normalizedToken, args[index + 1])) {
                index += 1;
            }
            else if (VALUE_FLAGS.has(normalizedToken) && !token.includes("=")) {
                index += 1;
            }
            else if (GLOBAL_BOOLEAN_FLAGS_WITH_OPTIONAL_VALUES.has(normalizedToken) &&
                !token.includes("=") &&
                isBooleanLiteral(args[index + 1])) {
                index += 1;
            }
            continue;
        }
        return index;
    }
    return undefined;
}
export function extractCommandTokens(args) {
    const commandStartIndex = findCommandStartIndex(args);
    return commandStartIndex === undefined ? [] : args.slice(commandStartIndex);
}
function getOpenCommandTarget(commandTokens) {
    for (let index = 1; index < commandTokens.length; index += 1) {
        const token = commandTokens[index];
        if (token === "--init-script" || token === "--enable") {
            index += 1;
            continue;
        }
        if (token.startsWith("--init-script=") || token.startsWith("--enable=")) {
            continue;
        }
        if (token.startsWith("-")) {
            continue;
        }
        return token;
    }
    return undefined;
}
export function parseCommandInfoFromTokens(commandTokens) {
    const command = commandTokens[0];
    return {
        command,
        subcommand: isOpenNavigationCommand(command) ? getOpenCommandTarget(commandTokens) : commandTokens[1],
    };
}
export function parseCommandInfo(args) {
    return parseCommandInfoFromTokens(extractCommandTokens(args));
}
export function parseArgvDescriptor(args) {
    const commandTokens = extractCommandTokens(args);
    return {
        commandInfo: parseCommandInfoFromTokens(commandTokens),
        commandTokens,
    };
}
