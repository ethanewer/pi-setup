import { type ModelThinkingLevel, type RunModelRegistry } from "./model-spec.js";
export declare class ModelRegistryRequiredError extends Error {
}
export interface SubagentModelConfig {
    /** Canonical `provider/id` of the chosen model. */
    model: string;
    /**
     * Pinned thinking level, or undefined for "no override". Kept separate from
     * `model` so ids containing colons (OpenRouter) and model ids that collide
     * with thinking names (`m:high`) stay unambiguous.
     */
    thinking?: ModelThinkingLevel;
}
export declare function getSubagentModelConfigPath(): string;
/** Read the single model. Preserve an existing installation's medium tier on migration. */
export declare function loadSubagentModelConfig(path?: string, legacyPath?: string, registry?: RunModelRegistry): SubagentModelConfig | null;
export declare function saveSubagentModelConfig(config: SubagentModelConfig, path?: string): void;
