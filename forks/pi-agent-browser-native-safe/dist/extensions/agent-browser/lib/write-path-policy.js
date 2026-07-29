/**
 * Purpose: Confine wrapper-created files and directories to operator-approved roots.
 * Responsibilities: Resolve requested artifact/output paths against the session workspace, follow symlinks before deciding, keep git metadata directories off limits, and report a single actionable message when a path escapes the approved roots.
 * Scope: Pure path policy; artifact preparation, output-file writing, and download shims call into it from their existing modules.
 * Invariants/Assumptions: The session cwd and the OS temp directory are always approved, extra roots and full opt-out come from user-owned environment variables only, and callers treat a returned message as a hard failure.
 */
import { readlinkSync, realpathSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, delimiter, dirname, isAbsolute, relative, resolve, sep } from "node:path";
export const ALLOWED_WRITE_ROOTS_ENV = "PI_AGENT_BROWSER_ALLOWED_WRITE_ROOTS";
export const UNCONFINED_WRITES_ENV = "PI_AGENT_BROWSER_ALLOW_UNCONFINED_WRITES";
const GIT_METADATA_DIRECTORY_NAME = ".git";
// Deliberately above every kernel symlink budget (32 on macOS, 40 on Linux) so a link chain long enough to exhaust
// this loop is also long enough for the write itself to fail with ELOOP; a shorter budget would resolve to a path
// still inside the workspace and allow the write.
const MAX_WRITE_PATH_SYMLINK_HOPS = 64;
function isTruthyEnvValue(value) {
    const normalized = value?.trim().toLowerCase();
    return normalized === "1" || normalized === "true" || normalized === "yes";
}
function pathIsWithin(path, parent) {
    const relativePath = relative(resolve(parent), resolve(path));
    return relativePath.length === 0 || (!relativePath.startsWith("..") && !isAbsolute(relativePath));
}
export function resolveRequestedWritePath(requestedPath, cwd) {
    return isAbsolute(requestedPath) ? resolve(requestedPath) : resolve(cwd, requestedPath);
}
function readSymlinkTarget(path) {
    try {
        return readlinkSync(path);
    }
    catch {
        return undefined;
    }
}
/**
 * Containment is decided on real paths so a symlink shipped inside the workspace cannot redirect a write out of
 * it. The requested file usually does not exist yet, so the deepest existing ancestor is resolved and the missing
 * segments are re-appended; the first missing segment is still followed when it is a dangling symlink, because a
 * write through it creates the link target rather than a file inside the workspace.
 * @param {string} absolutePath
 */
export function resolveRealWritePath(absolutePath) {
    let candidate = absolutePath;
    for (let hop = 0; hop <= MAX_WRITE_PATH_SYMLINK_HOPS; hop += 1) {
        const missingSegments = [];
        let existingAncestor = candidate;
        let realExistingAncestor;
        for (;;) {
            try {
                realExistingAncestor = realpathSync(existingAncestor);
                break;
            }
            catch {
                const parent = dirname(existingAncestor);
                if (parent === existingAncestor)
                    return candidate;
                missingSegments.unshift(basename(existingAncestor));
                existingAncestor = parent;
            }
        }
        const resolvedPath = resolve(realExistingAncestor, ...missingSegments);
        if (missingSegments.length === 0)
            return resolvedPath;
        const firstMissingPath = resolve(realExistingAncestor, missingSegments[0]);
        const linkTarget = readSymlinkTarget(firstMissingPath);
        if (linkTarget === undefined)
            return resolvedPath;
        candidate = resolve(dirname(firstMissingPath), linkTarget, ...missingSegments.slice(1));
    }
    return candidate;
}
/**
 * Windows drops trailing dots and spaces from a path component, so `.git.` and `.git ` open the real `.git` there
 * while naming a genuinely different directory on POSIX; the spelling is normalized only on the platform that folds it.
 * @param {string} segment
 */
function normalizePathSegmentForGitComparison(segment) {
    const lowercased = segment.toLowerCase();
    return process.platform === "win32" ? lowercased.replace(/[. ]+$/, "") : lowercased;
}
/** Writing into `.git` rewrites hooks, filters, or `core.hooksPath`, which runs on the next git command. */
function hasGitMetadataSegment(confinedRelativePath) {
    return confinedRelativePath
        .split(sep)
        .some((segment) => normalizePathSegmentForGitComparison(segment) === GIT_METADATA_DIRECTORY_NAME);
}
/**
 * Only the portion of the path at or below the deepest approved root is tested. Segments above a root are not part
 * of what the write creates, and a session cwd that itself lives inside a `.git` directory (a linked worktree admin
 * directory, for example) would otherwise fail every confined write closed.
 */
function getConfinedRelativeWritePath(absolutePath, cwd, env) {
    let confinedRelativePath;
    for (const root of getAllowedWriteRoots(cwd, env)) {
        if (!pathIsWithin(absolutePath, root))
            continue;
        const relativePath = relative(resolve(root), absolutePath);
        if (confinedRelativePath === undefined || relativePath.length < confinedRelativePath.length)
            confinedRelativePath = relativePath;
    }
    return confinedRelativePath;
}
/**
 * Deliberately independent of confinement: the artifact directory flags (`--download-path`, `--screenshot-dir`) are
 * policed by this check alone, so returning false for a target outside the approved roots would leave a `.git` write
 * through them unguarded. A path outside every approved root has no root to measure from, so the whole path is
 * tested; inside a root only the created portion is, which keeps a session cwd that itself lives under `.git` usable.
 */
export function isGitMetadataWritePath(requestedPath, cwd, env = process.env) {
    const absolutePath = resolveRealWritePath(resolveRequestedWritePath(requestedPath, cwd));
    const confinedRelativePath = getConfinedRelativeWritePath(absolutePath, cwd, env);
    return hasGitMetadataSegment(confinedRelativePath ?? absolutePath);
}
export function getAllowedWriteRoots(cwd, env = process.env) {
    const configuredRoots = (env[ALLOWED_WRITE_ROOTS_ENV] ?? "")
        .split(delimiter)
        .map((root) => root.trim())
        .filter((root) => root.length > 0)
        .map((root) => resolveRequestedWritePath(root, cwd));
    return [
        resolve(cwd),
        resolve(tmpdir()),
        ...(process.platform === "win32" ? [] : ["/tmp"]),
        ...configuredRoots,
    ].map((root) => resolveRealWritePath(root));
}
export function isConfinedWritePath(requestedPath, cwd, env = process.env) {
    if (isTruthyEnvValue(env[UNCONFINED_WRITES_ENV]))
        return true;
    const absolutePath = resolveRealWritePath(resolveRequestedWritePath(requestedPath, cwd));
    return getAllowedWriteRoots(cwd, env).some((root) => pathIsWithin(absolutePath, root));
}
export function getGitMetadataWriteError(requestedPath, cwd, label, env = process.env) {
    if (isTruthyEnvValue(env[UNCONFINED_WRITES_ENV]) || !isGitMetadataWritePath(requestedPath, cwd, env))
        return undefined;
    return [
        `Refusing to write ${label} ${JSON.stringify(requestedPath)} inside a git metadata directory.`,
        `A write under .git can install hooks or filters that run on the next git command, so agent_browser keeps it off limits even inside the workspace.`,
        `Use a path outside .git, or have the user approve unconfined writes by starting pi with ${UNCONFINED_WRITES_ENV}=1.`,
    ].join(" ");
}
/** Confinement is reported before git metadata so a path outside the approved roots gets the root cause, not a `.git` message about a location the caller could not write to anyway. */
export function getWritePathConfinementError(requestedPath, cwd, label, env = process.env) {
    if (isConfinedWritePath(requestedPath, cwd, env))
        return getGitMetadataWriteError(requestedPath, cwd, label, env);
    const absolutePath = resolveRequestedWritePath(requestedPath, cwd);
    const realPath = resolveRealWritePath(absolutePath);
    return [
        `Refusing to write ${label} ${JSON.stringify(requestedPath)} outside the session workspace${realPath === absolutePath ? "" : ` (it resolves through a symlink to ${realPath})`}.`,
        `agent_browser confines wrapper-created files to ${cwd} and the OS temp directory.`,
        `Use a path inside the workspace, or have the user approve the location by starting pi with ${ALLOWED_WRITE_ROOTS_ENV}=<root> (or ${UNCONFINED_WRITES_ENV}=1).`,
    ].join(" ");
}
