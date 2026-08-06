/**
 * Saved workflows as `/<name>` slash commands. Each saved workflow becomes a
 * command that runs its script, passing parsed arguments through as `args`.
 */
import { createCodingTools } from "@earendil-works/pi-coding-agent";
import { runWorkflow } from "./workflow.js";
import { loadWorkflowSettings } from "./workflow-settings.js";
function isRegistered(pi, name) {
    try {
        return (pi.getCommands?.() ?? []).some((c) => c.name === name);
    }
    catch {
        return false;
    }
}
/**
 * Ask before running a workflow whose script came from the project rather than
 * from the user. The prompt names the exact source: a repository can ship
 * `.pi/workflows/saved/<name>.json`, and cloning it must not be enough to make
 * `/<name>` start subagents — nor must copying a project-supplied run's script
 * into the user's own storage (see SavedWorkflow.scriptOrigin), which is why a
 * recorded origin gates the same way a repo-local file does. Declining is not an
 * error — it just doesn't run. Answered yes-by-configuration via
 * trustProjectLocalWorkflows.
 */
export async function confirmRepoLocalWorkflow(ctx, wf, cwd, purpose = `Run /${wf.name}?`) {
    if (!wf.repoLocal && !wf.scriptOrigin)
        return true;
    if (loadWorkflowSettings({ cwd }).trustProjectLocalWorkflows === true)
        return true;
    const source = wf.repoLocal ? wf.path : wf.scriptOrigin;
    const confirmed = await ctx.ui.confirm("Project-supplied workflow", `${purpose}\n\nIts script comes from this project's own directory:\n${source}\n\n` +
        "It will run subagents with your tools and permissions. Only continue if you trust this repository.");
    if (!confirmed) {
        ctx.ui.notify(`/${wf.name} was not run (project-supplied workflow declined).`, "info");
    }
    return confirmed;
}
function reportText(result) {
    const r = result.result;
    if (r && typeof r.report === "string" && r.report.trim())
        return r.report;
    return JSON.stringify(result.result, null, 2);
}
/**
 * Parse a command argument string into an `args` object for the script.
 * Supports `key=value` tokens; everything else collects into `_` (and `_raw`).
 * Declared parameter defaults fill in missing keys.
 */
export function parseCommandArgs(raw, parameters) {
    const out = {};
    const positional = [];
    for (const tok of raw.trim().split(/\s+/).filter(Boolean)) {
        const eq = tok.indexOf("=");
        if (eq > 0)
            out[tok.slice(0, eq)] = tok.slice(eq + 1);
        else
            positional.push(tok);
    }
    out._ = positional.join(" ");
    out._raw = raw.trim();
    for (const [key, spec] of Object.entries(parameters ?? {})) {
        if (out[key] === undefined && spec.default !== undefined)
            out[key] = spec.default;
    }
    return out;
}
/** Register one saved workflow as a `/<name>` command (idempotent).
 * When a WorkflowManager is provided, the workflow runs through it (visible in
 * /workflows TUI, background execution, task panel). Otherwise falls back to
 * the inline runWorkflow() (foreground, no TUI tracking).
 *
 * Pi has no `unregisterCommand`, so a command cannot be removed mid-session
 * after its workflow is deleted (it is correctly gone on next launch, since
 * registerAllSavedWorkflows only registers what's in storage). The optional
 * `exists` predicate lets the handler detect that case at invocation time and
 * tell the user to reload rather than silently re-running a deleted workflow. */
export function registerSavedWorkflow(pi, cwd, wf, manager, exists, 
/**
 * Live loader for this command's workflow. Prefer this over the registration-
 * time `wf` snapshot: after an in-process project switch the same slash
 * command name may resolve to a different script (or nothing) in the new
 * project's storage. When omitted, `wf` is used as a frozen snapshot.
 */
loadWorkflow) {
    if (isRegistered(pi, wf.name))
        return;
    const getCwd = typeof cwd === "function" ? cwd : () => cwd;
    const getManager = typeof manager === "function" ? manager : () => manager;
    pi.registerCommand(wf.name, {
        description: wf.description || `Saved workflow: ${wf.name}`,
        async handler(args, ctx) {
            // Resolve the workflow at invocation time so a cross-project session
            // switch picks up the target project's script (or reports deletion)
            // instead of replaying the source project's registration-time snapshot.
            const liveWf = loadWorkflow ? loadWorkflow() : exists && !exists() ? null : wf;
            if (!liveWf) {
                ctx.ui.notify(`/${wf.name} is not available in this project — reload the session to drop the stale command.`, "warning");
                return;
            }
            if (!(await confirmRepoLocalWorkflow(ctx, liveWf, getCwd())))
                return;
            try {
                const liveManager = getManager();
                if (liveManager) {
                    // Run through the WorkflowManager's background path: the handler
                    // returns immediately (awaiting the promise here would block the whole
                    // session, #104), progress shows in the /workflows TUI and task panel,
                    // and installResultDelivery posts the result back into the
                    // conversation on completion — sending it here too would duplicate it.
                    const { runId } = liveManager.startInBackground(liveWf.script, parseCommandArgs(args, liveWf.parameters));
                    ctx.ui.notify(`/${liveWf.name} running in the background (${runId}) — watch the task panel or /workflows; the result is posted here when it finishes.`, "info");
                    return;
                }
                // Fallback: inline runWorkflow (foreground, no TUI tracking, blocks).
                const liveCwd = getCwd();
                ctx.ui.notify(`Starting /${liveWf.name}…`, "info");
                const result = await runWorkflow(liveWf.script, {
                    cwd: liveCwd,
                    args: parseCommandArgs(args, liveWf.parameters),
                    tools: createCodingTools(liveCwd),
                    onPhase: (title) => ctx.ui.setStatus(`wf:${liveWf.name}`, `${liveWf.name}: ${title}`),
                });
                ctx.ui.setStatus(`wf:${liveWf.name}`, undefined);
                await pi.sendMessage({
                    customType: `workflow:${liveWf.name}`,
                    content: reportText(result),
                    display: true,
                });
            }
            catch (error) {
                ctx.ui.setStatus(`wf:${liveWf.name}`, undefined);
                ctx.ui.notify(`/${liveWf.name} failed: ${error instanceof Error ? error.message : error}`, "error");
            }
        },
    });
}
/** Register every saved workflow found in storage.
 * When a WorkflowManager is provided, workflows run through it (visible in
 * /workflows TUI, background execution, task panel). Idempotent: names already
 * registered (including from a previous project) are skipped at registration
 * time, but each handler re-loads by name from the live storage so a later
 * project switch executes the target project's script. Call again after a
 * cross-project session_start to pick up target-only names. */
export function registerAllSavedWorkflows(pi, cwd, storage, manager) {
    const getStorage = typeof storage === "function" ? storage : () => storage;
    const getCwd = typeof cwd === "function" ? cwd : () => cwd;
    for (const wf of getStorage().list()) {
        const name = wf.name;
        registerSavedWorkflow(pi, getCwd, wf, manager, () => getStorage().load(name) != null, () => getStorage().load(name));
    }
}
