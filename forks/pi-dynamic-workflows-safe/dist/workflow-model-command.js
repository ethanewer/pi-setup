import { THINKING_LEVELS } from "./model-spec.js";
import { loadSubagentModelConfig, saveSubagentModelConfig } from "./subagent-model-config.js";
/** Use Pi's resolved pins, including --models and pinned thinking levels. Never expand an empty scope. */
export function pinnedWorkflowModels(ctx) {
    const byKey = new Map();
    for (const { model, thinkingLevel } of ctx.scopedModels) {
        const canonical = `${model.provider}/${model.id}`;
        // Identity is the canonical id alone; the pinned thinking is metadata.
        const key = canonical;
        const existing = byKey.get(key);
        if (existing) {
            if (existing.thinkingLevel !== thinkingLevel) {
                // Same model pinned with different thinking levels: no single pin owns
                // the level, so the label drops the suffix and the pin's thinking
                // becomes "no explicit preference" (the user can still pick one in
                // the second dialog).
                existing.thinkingLevel = undefined;
                existing.label = canonical;
            }
            continue;
        }
        byKey.set(key, {
            model: canonical,
            thinkingLevel,
            label: thinkingLevel ? `${canonical}:${thinkingLevel}` : canonical,
        });
    }
    // Numbered labels cannot collide even when literal ids contain our display syntax.
    return [...byKey.values()].map((option, index) => ({
        ...option,
        label: `${index + 1}. ${option.model}${option.thinkingLevel ? ` [thinking: ${option.thinkingLevel}]` : ""}`,
    }));
}
export function registerWorkflowModelCommand(pi, config = { load: loadSubagentModelConfig, save: saveSubagentModelConfig }) {
    const handler = async (_args, ctx) => {
        await ctx.waitForIdle();
        if (!ctx.hasUI)
            return;
        const options = pinnedWorkflowModels(ctx);
        if (options.length === 0) {
            ctx.ui.notify("No pinned models. Pin models with /scoped-models, then run /workflow-model.", "warning");
            return;
        }
        let current = null;
        try {
            current = config.load(undefined, undefined, ctx.modelRegistry);
        }
        catch {
            ctx.ui.notify("The saved subagent model config is invalid. Choose a model to replace it.", "warning");
        }
        const currentSummary = current ? `${current.model}${current.thinking ? `:${current.thinking}` : ""}` : undefined;
        const selected = await ctx.ui.select(`Subagent model${currentSummary ? ` • current: ${currentSummary}` : ""}`, options.map((option) => option.label));
        const chosen = selected && options.find((option) => option.label === selected);
        if (!chosen)
            return;
        const thinking = await ctx.ui.select("Subagent thinking", ["Use pinned/default thinking", ...THINKING_LEVELS]);
        if (!thinking)
            return;
        const level = THINKING_LEVELS.find((value) => value === thinking);
        const save = {
            model: chosen.model,
            // An explicit choice wins over the pin's level; "default" keeps the pin's
            // level only when the user never overrides it here.
            thinking: level ?? chosen.thinkingLevel,
        };
        try {
            config.save(save);
        }
        catch (error) {
            ctx.ui.notify(`Could not save subagent model: ${String(error)}`, "error");
            return;
        }
        const summary = `${save.model}${save.thinking ? `:${save.thinking}` : ""}`;
        ctx.ui.notify(`Subagent model saved: ${summary}. Applies to new workflow runs.`, "info");
    };
    pi.registerCommand("workflow-model", { description: "Choose the single subagent model from pinned models", handler });
}
