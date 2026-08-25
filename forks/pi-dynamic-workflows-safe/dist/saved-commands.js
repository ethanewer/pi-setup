/**
 * Saved workflows as `/<name>` slash commands. Each saved workflow becomes a
 * command that runs its script, passing parsed arguments through as `args`.
 */
import { createCodingTools } from "@earendil-works/pi-coding-agent";
import { claimCommand, commandOwner, isCommandRegistered } from "./command-registry.js";
import { runWorkflow } from "./workflow.js";
import { loadWorkflowSettings } from "./workflow-settings.js";
function savedCommandOwnedByExtension(pi, name) {
    const owner = commandOwner(pi, name);
    return owner === "builtin" || owner === "saved";
}
/**
 * Pi cannot unregister a slash command. Distinguish commands this extension
 * owns from built-ins/other extensions before a save or rename reaches disk.
 */
export function savedWorkflowCommandAvailability(pi, name) {
    if (!isCommandRegistered(pi, name) || savedCommandOwnedByExtension(pi, name))
        return { ok: true };
    return { ok: false, message: `/${name} is already provided by Pi or another extension.` };
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
export function parseCommandArgs(raw, parameters) {
    const out = {};
    const positional = [];
    for (const token of raw.trim().split(/\s+/).filter(Boolean)) {
        const eq = token.indexOf("=");
        if (eq > 0)
            out[token.slice(0, eq)] = token.slice(eq + 1);
        else
            positional.push(token);
    }
    out._ = positional.join(" ");
    out._raw = raw.trim();
    for (const [key, spec] of Object.entries(parameters ?? {})) {
        if (out[key] === undefined && spec.default !== undefined)
            out[key] = spec.default;
    }
    return out;
}
/** Register one saved workflow as a dynamically loaded slash command. */
export function registerSavedWorkflow(pi, cwd, wf, manager, exists, loadWorkflow) {
    const availability = savedWorkflowCommandAvailability(pi, wf.name);
    if (!availability.ok)
        return availability;
    if (isCommandRegistered(pi, wf.name))
        return { ok: true };
    const getCwd = typeof cwd === "function" ? cwd : () => cwd;
    const getManager = typeof manager === "function" ? manager : () => manager;
    try {
        pi.registerCommand(wf.name, {
            description: wf.description || `Saved workflow: ${wf.name}`,
            async handler(args, ctx) {
                // Resolve at invocation so project switches and deletion cannot replay a stale script.
                const liveWorkflow = loadWorkflow ? loadWorkflow() : exists && !exists() ? null : wf;
                if (!liveWorkflow) {
                    ctx.ui.notify(`/${wf.name} is not available in this project — reload the session to drop the stale command.`, "warning");
                    return;
                }
                if (!(await confirmRepoLocalWorkflow(ctx, liveWorkflow, getCwd())))
                    return;
                try {
                    const liveManager = getManager();
                    if (liveManager) {
                        const { runId } = liveManager.startInBackground(liveWorkflow.script, parseCommandArgs(args, liveWorkflow.parameters));
                        ctx.ui.notify(`/${liveWorkflow.name} running in the background (${runId}) — watch the task panel or /workflows; the result is posted here when it finishes.`, "info");
                        return;
                    }
                    const liveCwd = getCwd();
                    ctx.ui.notify(`Starting /${liveWorkflow.name}…`, "info");
                    const result = await runWorkflow(liveWorkflow.script, {
                        cwd: liveCwd,
                        args: parseCommandArgs(args, liveWorkflow.parameters),
                        tools: createCodingTools(liveCwd),
                        onPhase: (title) => ctx.ui.setStatus(`wf:${liveWorkflow.name}`, `${liveWorkflow.name}: ${title}`),
                    });
                    ctx.ui.setStatus(`wf:${liveWorkflow.name}`, undefined);
                    await pi.sendMessage({
                        customType: `workflow:${liveWorkflow.name}`,
                        content: reportText(result),
                        display: true,
                    });
                }
                catch (error) {
                    ctx.ui.setStatus(`wf:${liveWorkflow.name}`, undefined);
                    ctx.ui.notify(`/${liveWorkflow.name} failed: ${error instanceof Error ? error.message : error}`, "error");
                }
            },
        });
        claimCommand(pi, wf.name, "saved");
        return { ok: true };
    }
    catch (error) {
        return { ok: false, message: error instanceof Error ? error.message : String(error) };
    }
}
export function registerAllSavedWorkflows(pi, cwd, storage, manager) {
    const getStorage = typeof storage === "function" ? storage : () => storage;
    const getCwd = typeof cwd === "function" ? cwd : () => cwd;
    for (const workflow of getStorage().list()) {
        const name = workflow.name;
        registerSavedWorkflow(pi, getCwd, workflow, manager, () => getStorage().load(name) != null, () => getStorage().load(name));
    }
}
