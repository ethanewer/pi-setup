/**
 * Purpose: Own machine-readable agent_browser next-action contracts and merge policy.
 * Responsibilities: Define the stable nextAction shape, build basic argv follow-ups, and provide deterministic action-list collection helpers.
 * Scope: Result follow-up action mechanics only; command-specific recovery and artifact policies live in neighboring modules.
 * Usage: Imported by result presentation helpers and the extension entrypoint when attaching details.nextActions.
 * Invariants/Assumptions: Action ids are stable machine-readable contracts; dedupe preserves first occurrence order.
 */
export function withOptionalNamespaceArgs(namespace, args) {
    return namespace && args[0] !== "--namespace" ? ["--namespace", namespace, ...args] : args;
}
export function withOptionalSessionArgs(sessionName, args) {
    if (!sessionName || args[0] === "--session")
        return args;
    if (args[0] === "--namespace" && args[1] && args[2] !== "--session")
        return [args[0], args[1], "--session", sessionName, ...args.slice(2)];
    return ["--session", sessionName, ...args];
}
export function applyNamespaceToNextActions(actions, namespace) {
    if (!namespace || !actions)
        return actions;
    return actions.map((action) => {
        const args = action.params?.args;
        if (args)
            return { ...action, params: { ...action.params, args: withOptionalNamespaceArgs(namespace, args) } };
        const networkSourceLookup = action.params?.networkSourceLookup;
        return networkSourceLookup ? { ...action, params: { ...action.params, networkSourceLookup: { ...networkSourceLookup, namespace } } } : action;
    });
}
export function buildNextToolAction(options) {
    return {
        id: options.id,
        params: {
            args: options.args,
            ...(options.sessionMode ? { sessionMode: options.sessionMode } : {}),
            ...(options.stdin ? { stdin: options.stdin } : {}),
        },
        reason: options.reason,
        ...(options.safety ? { safety: options.safety } : {}),
        tool: "agent_browser",
    };
}
export function appendUniqueAgentBrowserNextActions(target, additions) {
    if (!additions || additions.length === 0)
        return target;
    const existingIds = new Set(target.map((action) => action.id));
    for (const action of additions) {
        if (existingIds.has(action.id))
            continue;
        target.push(action);
        existingIds.add(action.id);
    }
    return target;
}
export function isStandaloneSnapshotNextAction(action) {
    const args = action.params?.args;
    if (!args || action.params?.stdin)
        return false;
    const commandIndex = args[0] === "--session" ? 2 : 0;
    return args[commandIndex] === "snapshot";
}
export function alignPageChangeSummaryNextActionIds(summary, nextActions) {
    if (!summary?.nextActionIds || !nextActions)
        return summary;
    const nextActionIds = new Set(nextActions.map((action) => action.id));
    const alignedIds = summary.nextActionIds.filter((id) => nextActionIds.has(id));
    return alignedIds.length > 0 ? { ...summary, nextActionIds: alignedIds } : { ...summary, nextActionIds: undefined };
}
export class AgentBrowserNextActionCollector {
    actions;
    constructor(initialActions = undefined) {
        this.actions = initialActions ? [...initialActions] : [];
    }
    append(actions) {
        if (!actions || actions.length === 0)
            return;
        this.actions.push(...actions);
    }
    appendUnique(actions) {
        appendUniqueAgentBrowserNextActions(this.actions, actions);
    }
    replace(actions) {
        this.actions = actions ? [...actions] : [];
    }
    removeWhere(predicate) {
        this.actions = this.actions.filter((action) => !predicate(action));
    }
    toArray() {
        return this.actions.length > 0 ? [...this.actions] : undefined;
    }
}
