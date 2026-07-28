function validateUserBatchStep(step, index) {
    if (!Array.isArray(step)) {
        return {
            error: `agent_browser batch stdin step ${index} must be a non-empty array of string command tokens.`,
            ok: false,
        };
    }
    if (step.length === 0) {
        return {
            error: `agent_browser batch stdin step ${index} must not be empty.`,
            ok: false,
        };
    }
    const invalidTokenIndex = step.findIndex((token) => typeof token !== "string");
    if (invalidTokenIndex !== -1) {
        return {
            error: `agent_browser batch stdin step ${index} token ${invalidTokenIndex} must be a string.`,
            ok: false,
        };
    }
    return { ok: true, step: step };
}
export function parseBatchStdinJsonArray(stdin) {
    if (stdin === undefined) {
        return { steps: [] };
    }
    try {
        const parsed = JSON.parse(stdin);
        if (!Array.isArray(parsed)) {
            return { error: "agent_browser batch stdin must be a JSON array of command steps." };
        }
        return { steps: parsed };
    }
    catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        return { error: `agent_browser batch stdin could not be parsed as JSON: ${message}` };
    }
}
export function parseUserBatchStdin(stdin) {
    const parsed = parseBatchStdinJsonArray(stdin);
    if (parsed.error || parsed.steps === undefined) {
        return parsed.error ? { error: parsed.error } : { steps: [] };
    }
    const steps = [];
    for (const [index, rawStep] of parsed.steps.entries()) {
        const validated = validateUserBatchStep(rawStep, index);
        if (!validated.ok) {
            return { error: validated.error };
        }
        steps.push(validated.step);
    }
    return { steps };
}
export function parseValidBatchStepEntries(stdin) {
    const parsed = parseBatchStdinJsonArray(stdin);
    if (parsed.error || parsed.steps === undefined)
        return [];
    return parsed.steps.flatMap((step, index) => {
        const validated = validateUserBatchStep(step, index);
        return validated.ok ? [{ index, step: validated.step }] : [];
    });
}
