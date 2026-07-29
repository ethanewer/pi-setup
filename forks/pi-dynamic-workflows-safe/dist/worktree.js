/**
 * Per-agent git worktree isolation. When an agent requests `isolation: "worktree"`,
 * it runs in a throwaway worktree on its own branch so parallel agents can edit the
 * same files without conflict. Results are NOT auto-merged — the path is surfaced for
 * the caller to inspect. Falls back to a logged no-op when isolation isn't possible.
 */
import { execFile } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { promisify } from "node:util";
const exec = promisify(execFile);
/**
 * Directory/branch id for a worktree. The readable slug is truncated, and the
 * names passed in (`<runId>-<callIndex>-<label>`) share a long runId prefix, so
 * the slug ALONE collides across agents of the same run — every colliding agent
 * but the first would fail `git worktree add` and fall back to the shared tree,
 * i.e. silently lose the isolation the caller asked for. The full name's digest
 * is what makes the id unique; it stays deterministic, so resume keys are stable.
 */
export function worktreeId(name) {
    const slug = name
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, "-")
        .replace(/^-+|-+$/g, "")
        .slice(0, 32) || "agent";
    return `${slug}-${createHash("sha256").update(name).digest("hex").slice(0, 12)}`;
}
/**
 * Keep the worktree directory — which lives inside the repository — out of the
 * repository's own history. Best-effort: an unwritable path just means the user
 * sees the directory as untracked.
 */
function ignoreWorktreeDir(dir) {
    try {
        mkdirSync(dir, { recursive: true, mode: 0o700 });
        const ignore = join(dir, ".gitignore");
        if (!existsSync(ignore))
            writeFileSync(ignore, "*\n", "utf-8");
    }
    catch {
        // Not fatal — git worktree add creates what it needs itself.
    }
}
/**
 * Create an isolated worktree under `<repoRoot>/.pi/worktrees/<id>` on branch
 * `pi/wf/<id>`. The `name` must be deterministic (derived from runId + call index,
 * never wall-clock) so resume keys stay stable. Returns a no-op Worktree carrying
 * the reason on failure; the CALLER decides whether running unisolated is
 * acceptable (see WorkflowRunOptions.isolationFallback) — it never is by default.
 */
export async function createWorktree(baseCwd, name) {
    const id = worktreeId(name);
    let repoRoot;
    try {
        const { stdout } = await exec("git", ["-C", baseCwd, "rev-parse", "--show-toplevel"]);
        repoRoot = stdout.trim();
    }
    catch (error) {
        // Only a git that RAN and refused counts as "there is no repository here".
        // A spawn failure (git not installed / not on PATH) and a repository git
        // declines to touch (`detected dubious ownership`) are failures of the
        // check, not evidence about the directory — reporting them as
        // noRepository would hand them the not-a-repository fallback and quietly
        // run an agent that asked for isolation in the shared working tree (see
        // WorkflowRunOptions.isolationFallback).
        const exitCode = error.code;
        const stderr = String(error.stderr ?? "");
        const ran = typeof exitCode === "number";
        const declinedRepo = /dubious ownership/i.test(stderr);
        if (!ran || declinedRepo) {
            const detail = (stderr.split("\n").find((line) => line.trim().length > 0) ?? "").trim();
            return {
                isolated: false,
                cwd: baseCwd,
                reason: `git could not be consulted here${detail ? `: ${detail}` : ` (${String(exitCode)})`}`,
            };
        }
        return { isolated: false, cwd: baseCwd, reason: "not a git repository", noRepository: true };
    }
    const worktreesDir = join(repoRoot, ".pi", "worktrees");
    ignoreWorktreeDir(worktreesDir);
    const path = join(worktreesDir, id);
    const branch = `pi/wf/${id}`;
    try {
        await exec("git", ["-C", repoRoot, "worktree", "add", "-b", branch, path, "HEAD"]);
        return { isolated: true, cwd: path, branch, repoRoot };
    }
    catch (error) {
        return { isolated: false, cwd: baseCwd, reason: error instanceof Error ? error.message : String(error) };
    }
}
/** Remove a worktree and its branch. Best-effort; safe to call on a no-op Worktree. */
export async function removeWorktree(wt) {
    if (!wt.isolated || !wt.repoRoot)
        return;
    try {
        await exec("git", ["-C", wt.repoRoot, "worktree", "remove", "--force", wt.cwd]);
    }
    catch {
        // already gone / locked — fall through
    }
    if (wt.branch) {
        try {
            await exec("git", ["-C", wt.repoRoot, "branch", "-D", wt.branch]);
        }
        catch {
            // branch already deleted
        }
    }
}
