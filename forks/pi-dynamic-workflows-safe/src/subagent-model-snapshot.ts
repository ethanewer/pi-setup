import { clampThinkingLevel } from "@earendil-works/pi-ai";
import { getAgentDir, SettingsManager, ModelRegistry, ModelRuntime, type CreateAgentSessionOptions } from "@earendil-works/pi-coding-agent";
import { canonicalModelSpec, isThinkingLevel, resolveRunModelStrict, type ModelThinkingLevel } from "./model-spec.js";
import { loadSubagentModelConfig, ModelRegistryRequiredError } from "./subagent-model-config.js";

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
export function resolveSubagentSnapshot(options: SubagentSnapshotOptions): SubagentSnapshot {
  const explicit = options.subagentModel !== undefined;
  const config = explicit ? null : loadSubagentModelConfig(options.subagentModelConfigPath, undefined, options.modelRegistry);
  // A supplied pair is already a snapshot, not another preference lookup.
  if (explicit && options.subagentThinking !== undefined) {
    if (!isThinkingLevel(options.subagentThinking)) throw new Error("Invalid subagent thinking level.");
    return {
      subagentModel: canonicalizeModel(options.subagentModel!, options.modelRegistry),
      subagentThinking: options.subagentThinking,
    };
  }
  const settings = options.session?.settingsManager ?? SettingsManager.create(options.cwd ?? process.cwd(), getAgentDir());
  const restored = options.session?.sessionManager?.buildSessionContext();
  const restoredModel = restored?.messages.length ? restored.model : undefined;
  const sessionModel = options.session?.model ?? (restoredModel && options.modelRegistry?.find(restoredModel.provider, restoredModel.modelId));
  const defaultProvider = settings.getDefaultProvider();
  const defaultId = settings.getDefaultModel();
  // Host session model wins over settings defaults; neither overrides a saved
  // subagent choice or the run's main model.
  let subagentModel = options.subagentModel ?? config?.model ?? options.mainModel ??
    (sessionModel ? `${sessionModel.provider}/${sessionModel.id}` : undefined) ??
    (defaultProvider && defaultId ? `${defaultProvider}/${defaultId}` : "");
  // Early files copied bare ids or aggregator vendor/model paths. A unique
  // literal match is rewritten to provider/id; anything else stays for the
  // runner to reject. Bare ids cannot be interpreted without a registry.
  if (subagentModel && !subagentModel.includes("/") && !options.modelRegistry) {
    throw new ModelRegistryRequiredError("Resolving a bare model id requires a registry.");
  }
  if (subagentModel && options.modelRegistry) subagentModel = canonicalizeModel(subagentModel, options.modelRegistry);
  if (!subagentModel && !explicit) {
    if (!options.modelRegistry) throw new ModelRegistryRequiredError("Default model selection requires a registry.");
    const available = options.modelRegistry.getAvailable();
    if (available.length > 0) subagentModel = canonicalModelSpec(available[0]);
  }
  const slash = subagentModel.indexOf("/");
  const requested = options.subagentThinking ?? config?.thinking ?? options.session?.thinkingLevel ??
    (restored?.messages.length && options.session?.sessionManager?.getBranch().some((entry) => entry.type === "thinking_level_change") ? restored.thinkingLevel : undefined) ??
    (slash > 0 ? settings.getModelThinkingLevel(subagentModel.slice(0, slash), subagentModel.slice(slash + 1)) : undefined) ??
    settings.getDefaultThinkingLevel() ?? "medium";
  if (!isThinkingLevel(requested)) throw new Error("Invalid subagent thinking level. Use /workflow-model to choose one.");
  const model = options.modelRegistry ? resolveRunModelStrict(subagentModel, options.modelRegistry).model : undefined;
  return {
    subagentModel,
    // The SDK applies the same capability clamp at session creation when an
    // embedder has not provided a registry. The requested level is still frozen.
    subagentThinking: model ? clampThinkingLevel(model, requested) : requested,
  };
}

function canonicalizeModel(spec: string, registry?: ModelRegistry): string {
  if (!spec || !registry) return spec;
  return resolveRunModelStrict(spec, registry).resolvedSpec ?? spec;
}

/** Resolve synchronously when possible; initialize the SDK registry only when needed. */
export function prepareSubagentSnapshot(options: SubagentSnapshotOptions): SubagentSnapshot | Promise<SubagentSnapshot> {
  try {
    return resolveSubagentSnapshot(options);
  } catch (error) {
    if (!(error instanceof ModelRegistryRequiredError)) throw error;
    return (async () => {
      const agentDir = options.session?.agentDir ?? getAgentDir();
      const runtime = options.session?.modelRuntime ?? await ModelRuntime.create({
        authPath: `${agentDir}/auth.json`, modelsPath: `${agentDir}/models.json`,
      });
      await runtime.getAvailable();
      return resolveSubagentSnapshot({ ...options, modelRegistry: new ModelRegistry(runtime) });
    })();
  }
}
