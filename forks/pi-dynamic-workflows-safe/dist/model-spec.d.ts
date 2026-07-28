import type { Api, Model } from "@earendil-works/pi-ai";
import type { ModelRegistry } from "@earendil-works/pi-coding-agent";
export declare const THINKING_LEVELS: readonly ["off", "minimal", "low", "medium", "high", "xhigh", "max"];
export type ModelThinkingLevel = (typeof THINKING_LEVELS)[number];
export interface ResolvedModelSpec {
    requestedSpec: string;
    model?: Model<Api>;
    thinkingLevel?: ModelThinkingLevel;
    resolvedSpec?: string;
    warning?: string;
    error?: string;
}
export declare function isThinkingLevel(value: string): value is ModelThinkingLevel;
export declare function formatModelSpecWithThinking(modelSpec: string, thinkingLevel: ModelThinkingLevel | undefined): string;
export declare function canonicalModelSpec(model: Model<Api>): string;
/**
 * Split a stored tier spec for display/editing. Exact known model specs win, so
 * model ids that legitimately contain colons are not mistaken for thinking.
 */
export declare function splitModelSpecThinking(spec: string | undefined, knownModelSpecs?: readonly string[]): {
    modelSpec: string;
    thinkingLevel?: ModelThinkingLevel;
};
/**
 * Resolve a workflow model-tier/agent model string with the same user-facing
 * grammar as Pi CLI `--model`: `provider/modelId[:thinking]`, bare model ids,
 * fuzzy patterns, and exact colon-containing model ids.
 */
export declare function resolveModelSpecWithThinking(spec: string, modelRegistry: Pick<ModelRegistry, "getAll">): ResolvedModelSpec;
