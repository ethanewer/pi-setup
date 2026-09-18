import { ModelRegistry, type CreateAgentSessionOptions } from "@earendil-works/pi-coding-agent";
import { type ModelThinkingLevel } from "./model-spec.js";
export interface SubagentSnapshot {
    subagentModel: string;
    subagentThinking: ModelThinkingLevel;
}
export interface SubagentSnapshotOptions {
    cwd?: string;
    subagentModel?: string;
    subagentThinking?: string;
    mainModel?: string;
    subagentModelConfigPath?: string;
    modelRegistry?: ModelRegistry;
    session?: Partial<CreateAgentSessionOptions>;
}
/** Read preferences once. Callers persist/pass this pair, never the preferences. */
export declare function resolveSubagentSnapshot(options: SubagentSnapshotOptions): SubagentSnapshot;
/** Resolve synchronously when possible; initialize the SDK registry only when needed. */
export declare function prepareSubagentSnapshot(options: SubagentSnapshotOptions): SubagentSnapshot | Promise<SubagentSnapshot>;
