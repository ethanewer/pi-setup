/**
 * Purpose: Build session-aware recovery nextActions that combine result category policy with known session/tab context.
 * Responsibilities: Prefix recovery argv with the active session and adapt tab/about:blank/no-active/stale-ref contexts into stable nextAction lists.
 * Scope: Recovery nextAction assembly only; diagnostic detection and action-list merge ordering stay in the extension entrypoint.
 * Usage: Imported by the extension entrypoint when adding recovery nextActions to tool details.
 * Invariants/Assumptions: Action ids and argv ordering are public contracts; session prefixing must not double-prefix explicit --session args.
 */
import { buildAgentBrowserNextActions } from "./action-recommendations.js";
import { withOptionalSessionArgs } from "./next-actions.js";
export function buildConnectedSessionNextActions(sessionName) {
    if (!sessionName)
        return [];
    return buildAgentBrowserNextActions({
        recovery: { kind: "connected-session", sessionName },
        resultCategory: "success",
        successCategory: "completed",
    }) ?? [];
}
export function buildNoActivePageNextActions(sessionName) {
    if (!sessionName)
        return [];
    return buildAgentBrowserNextActions({
        recovery: { kind: "no-active-page", sessionName },
        resultCategory: "failure",
    }) ?? [];
}
export function buildSessionTabRecoveryNextActions(options) {
    const resultCategory = options.resultCategory ?? "success";
    return buildAgentBrowserNextActions({
        recovery: {
            kind: options.kind,
            recoveryApplied: options.recoveryApplied,
            selectedTab: options.tabCorrection?.selectedTab,
            sessionName: options.sessionName,
            targetTitle: options.tabCorrection?.targetTitle ?? options.target?.title,
            targetUrl: options.tabCorrection?.targetUrl ?? options.target?.url,
        },
        resultCategory,
        successCategory: resultCategory === "success" ? "completed" : undefined,
    }) ?? [];
}
export function buildSessionAwareStaleRefNextActions(sessionName) {
    return (buildAgentBrowserNextActions({ failureCategory: "stale-ref", resultCategory: "failure" }) ?? []).map((action) => {
        const actionArgs = action.params?.args;
        return {
            ...action,
            params: action.params && actionArgs ? { ...action.params, args: withOptionalSessionArgs(sessionName, actionArgs) } : action.params,
        };
    });
}
