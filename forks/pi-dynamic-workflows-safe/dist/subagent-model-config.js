import { existsSync, mkdirSync, readFileSync, renameSync, unlinkSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { randomUUID } from "node:crypto";
import { SUBAGENT_MODEL_FILE } from "./config.js";
import { isThinkingLevel, resolveRunModelStrict } from "./model-spec.js";
export class ModelRegistryRequiredError extends Error {
}
export function getSubagentModelConfigPath() {
    return join(homedir(), SUBAGENT_MODEL_FILE);
}
function validModel(value) {
    return typeof value === "string" && value.trim().length > 0;
}
function resolveIdentity(spec, registry) {
    const identity = resolveRunModelStrict(spec, registry);
    if (identity.model && identity.resolvedSpec)
        return { model: identity.resolvedSpec };
    throw new Error(`Saved model "${spec}" is unavailable or ambiguous. Use /workflow-model to choose one.`);
}
/** Legacy medium specs may still encode thinking as a suffix. Existing files never do. */
function resolveLegacyModel(spec, registry) {
    try {
        return resolveIdentity(spec, registry);
    }
    catch (identityError) {
        const colon = spec.lastIndexOf(":");
        const suffix = spec.slice(colon + 1);
        if (colon > 0 && isThinkingLevel(suffix)) {
            const base = resolveRunModelStrict(spec.slice(0, colon), registry);
            if (base.model && base.resolvedSpec)
                return { model: base.resolvedSpec, thinking: suffix };
        }
        throw identityError;
    }
}
function canonicalizeLoadedConfig(loaded, path, registry) {
    const resolved = resolveIdentity(loaded.model, registry);
    const next = { model: resolved.model };
    if (loaded.thinking !== undefined)
        next.thinking = loaded.thinking;
    if (next.model !== loaded.model || next.thinking !== loaded.thinking)
        saveSubagentModelConfig(next, path);
    return next;
}
/** Read the single model. Preserve an existing installation's medium tier on migration. */
export function loadSubagentModelConfig(path = getSubagentModelConfigPath(), legacyPath = join(dirname(path), "model-tiers.json"), registry) {
    if (existsSync(path)) {
        const config = JSON.parse(readFileSync(path, "utf8"));
        if (!validModel(config?.model))
            throw new Error(`Invalid subagent model in ${path}. Use /workflow-model to choose one.`);
        const loaded = { model: config.model.trim() };
        if (config.thinking !== undefined) {
            if (!isThinkingLevel(config.thinking))
                throw new Error(`Invalid thinking in ${path}. Use /workflow-model to choose one.`);
            loaded.thinking = config.thinking;
        }
        // Early files copied aggregator ids or bare ids verbatim. Rewrite only a
        // unique interpretation so later loads stay canonical.
        return registry ? canonicalizeLoadedConfig(loaded, path, registry) : loaded;
    }
    if (!existsSync(legacyPath))
        return null;
    const legacy = JSON.parse(readFileSync(legacyPath, "utf8"));
    const model = legacy?.tiers?.medium;
    if (!validModel(model))
        throw new Error(`Cannot migrate ${legacyPath}: no medium model. Use /workflow-model to choose one.`);
    const spec = model.trim();
    // Resolve the legacy identity against the registry before writing. A bare id
    // may be ambiguous across providers, a slash-containing id may be an
    // aggregator path that only resolves under a prefixed provider, and a
    // thinking-looking suffix may be a literal model id. The legacy resolver
    // matched literal ids first, so only a unique interpretation migrates;
    // anything else fails without creating the new file.
    if (!registry) {
        throw new ModelRegistryRequiredError(`Migrating ${legacyPath} requires a model registry.`);
    }
    try {
        const config = resolveLegacyModel(spec, registry);
        saveSubagentModelConfig(config, path);
        // Keep the old file as a rollback copy; it is never consulted once the new file exists.
        return config;
    }
    catch (error) {
        throw new Error(error instanceof Error
            ? error.message.replace(/^Saved model/, "Legacy model")
            : `Legacy model "${spec}" is unavailable or ambiguous. Use /workflow-model to choose one.`);
    }
}
export function saveSubagentModelConfig(config, path = getSubagentModelConfigPath()) {
    if (!validModel(config?.model))
        throw new Error("A non-empty subagent model is required.");
    if (config.thinking !== undefined && !isThinkingLevel(config.thinking)) {
        throw new Error("Thinking must be a supported level or omitted.");
    }
    mkdirSync(dirname(path), { recursive: true, mode: 0o700 });
    const trimmed = { model: config.model.trim() };
    if (config.thinking !== undefined)
        trimmed.thinking = config.thinking;
    const temp = `${path}.${randomUUID()}.tmp`;
    try {
        writeFileSync(temp, `${JSON.stringify(trimmed, null, 2)}\n`, { mode: 0o600, flag: "wx" });
        renameSync(temp, path);
    }
    finally {
        if (existsSync(temp))
            unlinkSync(temp);
    }
}
