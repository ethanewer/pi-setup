import type { ExtensionAPI, ExtensionCommandContext } from "@earendil-works/pi-coding-agent";
import { type ModelThinkingLevel } from "./model-spec.js";
import { loadSubagentModelConfig, saveSubagentModelConfig } from "./subagent-model-config.js";
export interface PinnedModelOption {
    /** Canonical provider/id, the value saved to config. */
    model: string;
    /** Thinking level pinned alongside the model, or undefined. */
    thinkingLevel?: ModelThinkingLevel;
    /** Display label, including the pinned thinking when present. */
    label: string;
}
/** Use Pi's resolved pins, including --models and pinned thinking levels. Never expand an empty scope. */
export declare function pinnedWorkflowModels(ctx: Pick<ExtensionCommandContext, "scopedModels">): PinnedModelOption[];
export declare function registerWorkflowModelCommand(pi: ExtensionAPI, config?: {
    load: typeof loadSubagentModelConfig;
    save: typeof saveSubagentModelConfig;
}): void;
