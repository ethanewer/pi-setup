import { constants, existsSync } from "node:fs";
import { createHash } from "node:crypto";
import { lstat, mkdir, open, readlink, realpath } from "node:fs/promises";
import { basename, dirname, isAbsolute, join, normalize, relative, resolve, sep } from "node:path";
import type { ResolvedProjectContext } from "./types.ts";
import { SymlinkDestinationError, writeFileAtomic } from "./atomic-write.ts";
import { recordPackageWrite, wasWrittenByPackage } from "./write-provenance.ts";

interface ExecApi {
	exec(command: string, args: string[], options?: { cwd?: string; timeout?: number }): Promise<{
		stdout: string;
		code: number;
	}>;
}

const DEFAULT_AGENT_GUIDE_PATH = "AGENTS.md";
// Repo-owned machinery that a configured output path must never reach.
const REFUSED_PATH_SEGMENTS = new Set<string>([".git"]);
const CONTINUATION_ARTIFACT_GITIGNORE = [
	"# pi-continue session briefs can quote file contents; keep them out of commits.",
	"*",
	"",
].join("\n");
// A guide or artifact this package reads or replaces is a document, not a data set; anything
// larger is a link to something that is not one.
const MAX_READ_BYTES = 4_000_000;
// O_NOFOLLOW keeps the final open on the already-resolved location even if a symlink is planted
// there afterwards; O_NONBLOCK keeps the open itself from waiting on a device or FIFO.
const READ_FLAGS = constants.O_RDONLY | (constants.O_NOFOLLOW ?? 0) | (constants.O_NONBLOCK ?? 0);
const mutationQueues = new Map<string, Promise<unknown>>();
// Digest of what this package last wrote at a path in this session, so its own output stays
// replaceable without approval while an edit someone else made afterwards still asks.
const packageWrittenDigests = new Map<string, string>();

export type MarkdownWriteRefusal =
	| "outside-project"
	| "reserved-path"
	| "overwrite-declined"
	| "redirected-path"
	| "redirected-file";

export interface NormalizedMarkdownWriteOptions {
	/** Require the symlink-resolved target to stay inside this root. */
	containmentRoot?: string;
	/** Require the target to be its literal location, so no symlink on the path can redirect the write. */
	refuseRedirectedPath?: boolean;
	/** Permit a target whose real path leaves the containment root, for an operator-configured escape. */
	allowOutsideRoot?: boolean;
	/** Permit a symlinked parent directory an operator created on purpose, such as a shared .pi. */
	allowSymlinkedAncestor?: boolean;
	/** Approve replacing pre-existing content this package did not write; omitted means no approval is needed. */
	confirmOverwrite?: (path: string) => Promise<boolean>;
	/** Remember a digest of what was written so a later session recognizes this package's own output. */
	trackProvenance?: boolean;
}

export class MarkdownWriteRefusedError extends Error {
	readonly reason: MarkdownWriteRefusal;

	constructor(reason: MarkdownWriteRefusal, message: string) {
		super(message);
		this.reason = reason;
	}
}

async function withMutationQueue<T>(path: string, work: () => Promise<T>): Promise<T> {
	const previous = mutationQueues.get(path) ?? Promise.resolve();
	const next = previous.then(work, work);
	mutationQueues.set(path, next);
	try {
		return await next;
	} finally {
		if (mutationQueues.get(path) === next) mutationQueues.delete(path);
	}
}

function trimTrailingWhitespace(value: string): string {
	return value
		.replace(/\r\n/g, "\n")
		.split("\n")
		.map((line) => line.replace(/[ \t]+$/g, ""))
		.join("\n")
		.trim();
}

/** Normalize markdown content before diffing or writing. */
export function normalizeMarkdownContent(value: string): string {
	return `${trimTrailingWhitespace(value)}\n`;
}

async function getGitRoot(pi: ExecApi, cwd: string): Promise<string | undefined> {
	const result = await pi.exec("git", ["rev-parse", "--show-toplevel"], { cwd, timeout: 4000 });
	if (result.code !== 0) return undefined;
	const root = result.stdout.trim();
	return root.length > 0 ? root : undefined;
}

export async function resolveProjectRoot(pi: ExecApi, cwd: string): Promise<string> {
	return (await getGitRoot(pi, cwd)) ?? cwd;
}

function isInsideRoot(root: string, candidate: string): boolean {
	const rel = relative(root, candidate);
	return rel.length > 0 && rel !== ".." && !rel.startsWith(`..${sep}`) && !isAbsolute(rel);
}

function hasRefusedSegment(root: string, candidate: string): boolean {
	return pathHasRefusedSegment(relative(root, candidate));
}

function pathHasRefusedSegment(path: string): boolean {
	return path.split(sep).some((segment) => REFUSED_PATH_SEGMENTS.has(segment));
}

async function realpathOrUndefined(path: string): Promise<string | undefined> {
	try {
		return await realpath(path);
	} catch {
		return undefined;
	}
}

// Resolve symlinks on the deepest existing ancestor so a repo-relative path cannot leave
// the project through a symlinked directory, whether or not the target exists yet.
async function resolveRealPath(path: string): Promise<string> {
	const absolute = resolve(path);
	const direct = await realpathOrUndefined(absolute);
	if (direct !== undefined) return direct;
	const parent = dirname(absolute);
	if (parent === absolute) return absolute;
	return join(await resolveRealPath(parent), basename(absolute));
}

/** Resolve a path to its real location, or undefined when it escapes the project or a refused directory. */
export async function resolveContainedProjectPath(projectRoot: string, candidatePath: string): Promise<string | undefined> {
	const realRoot = await resolveRealPath(projectRoot);
	const realCandidate = await resolveRealPath(candidatePath);
	if (!isInsideRoot(realRoot, realCandidate)) return undefined;
	if (hasRefusedSegment(realRoot, realCandidate)) return undefined;
	return realCandidate;
}

async function isSymbolicLink(path: string): Promise<boolean> {
	try {
		return (await lstat(path)).isSymbolicLink();
	} catch {
		return false;
	}
}

// A symlink at the output path itself aims a full-file replacement at whatever it points at, so it
// is never followed and no setting waives it. The destination is read from the link rather than
// resolved, so a link into a location that does not exist yet is still reported accurately.
async function assertOutputFileIsNotSymlink(candidatePath: string): Promise<void> {
	const absolute = resolve(candidatePath);
	if (!(await isSymbolicLink(absolute))) return;
	const destination = await readlink(absolute).catch(() => undefined);
	throw new MarkdownWriteRefusedError(
		"redirected-file",
		`Output path ${absolute} is a symlink${destination === undefined ? "" : ` to ${destination}`}; refusing to replace the file it points at.`,
	);
}

// Package-owned paths have exactly one legitimate location, so a symlink at the file or on any
// directory above it inside the project is a redirection rather than a supported layout. Node has
// no openat, so the remaining window is between this check and the write itself. A symlinked parent
// directory can be an operator's deliberate layout, so that half is separately waivable; a symlink
// at the output file itself never is, because it aims a full-file replacement at another file.
async function assertUnredirectedPath(root: string, candidatePath: string, allowSymlinkedAncestor = false): Promise<void> {
	await assertOutputFileIsNotSymlink(candidatePath);
	if (allowSymlinkedAncestor) return;
	const absolute = resolve(candidatePath);
	const expected = join(await resolveRealPath(root), relative(root, absolute));
	const realTarget = await resolveRealPath(absolute);
	const realParent = await resolveRealPath(dirname(absolute));
	if (realTarget === expected && realParent === dirname(expected)) return;
	throw new MarkdownWriteRefusedError(
		"redirected-path",
		`Resolved output path ${realTarget} is not the package-owned location ${expected}; refusing to write through a symlinked directory.`,
	);
}

function sanitizeRepoRelativePath(projectRoot: string, configuredPath: string, fallback: string): string {
	const trimmed = normalize(configuredPath.trim()).replace(/^\.\//, "");
	if (trimmed.length === 0) return fallback;
	if (isAbsolute(trimmed)) return fallback;
	const resolved = resolve(projectRoot, trimmed);
	const rel = relative(projectRoot, resolved);
	if (rel === "" || rel === ".." || rel.startsWith(`..${sep}`)) return fallback;
	if (hasRefusedSegment(projectRoot, resolved)) return fallback;
	return trimmed;
}

// The configured guide is always a repo-relative path, so it can only leave the project through a
// symlink. Whether such an escape may be read or written needs the operator's global opt-in either
// way, since a clone can commit that symlink.
function resolveAgentGuideTarget(projectRoot: string, configuredPath: string): string {
	return join(projectRoot, sanitizeRepoRelativePath(projectRoot, configuredPath, DEFAULT_AGENT_GUIDE_PATH));
}

interface GuardedReadResult {
	content: string | undefined;
	refusal: string | undefined;
}

// Anything a repo can commit may sit at a path this package reads, so the read is opened without
// blocking, checked for being a regular file, and capped before a single byte reaches memory: a
// link to a FIFO or a character device would otherwise hang the process and a huge file would
// exhaust it. Asynchronous throughout, so none of it runs on a blocking critical path.
async function readGuardedFile(path: string): Promise<GuardedReadResult> {
	let handle: Awaited<ReturnType<typeof open>>;
	try {
		handle = await open(path, READ_FLAGS);
	} catch {
		// A path that is absent, unreadable, or a symlink planted since it was resolved simply has
		// no content to offer; nothing here is a refusal the operator has to act on.
		return { content: undefined, refusal: undefined };
	}
	try {
		const stats = await handle.stat();
		if (!stats.isFile()) {
			return { content: undefined, refusal: `${path} is not a regular file, so pi-continue did not read it.` };
		}
		if (stats.size > MAX_READ_BYTES) {
			return {
				content: undefined,
				refusal: `${path} is ${stats.size} bytes, over the ${MAX_READ_BYTES}-byte limit pi-continue reads, so it was left out.`,
			};
		}
		return { content: await handle.readFile("utf8"), refusal: undefined };
	} catch {
		return { content: undefined, refusal: undefined };
	} finally {
		await handle.close().catch(() => undefined);
	}
}

async function readOptionalFile(path: string): Promise<string | undefined> {
	return (await readGuardedFile(path)).content;
}

// The configured guide feeds a summarizer prompt verbatim, so a guide that leaves the project
// through a symlink is exactly as much of a decision as writing outside it: an untrusted clone
// could otherwise point AGENTS.md at a private key and have it quoted into the handoff.
async function readContainedAgentGuide(
	projectRoot: string,
	guidePath: string,
	allowOutsideProject: boolean,
): Promise<GuardedReadResult> {
	const contained = await resolveContainedProjectPath(projectRoot, guidePath);
	if (contained !== undefined) return readGuardedFile(contained);
	const real = await resolveRealPath(guidePath);
	if (pathHasRefusedSegment(real)) {
		return { content: undefined, refusal: `Agent guide ${guidePath} resolves into repo-owned machinery at ${real}; pi-continue did not read it.` };
	}
	if (!allowOutsideProject) {
		return {
			content: undefined,
			refusal: `Agent guide ${guidePath} resolves to ${real}, outside ${projectRoot}; pi-continue did not read it.`,
		};
	}
	return readGuardedFile(real);
}

export function encodeSessionIdForArtifactPath(sessionId: string): string {
	const encoded = Buffer.from(sessionId, "utf8").toString("base64url");
	return encoded.length > 0 ? encoded : "empty-session-id";
}

export function buildContinuationArtifactPath(projectRoot: string, sessionId: string): string {
	return join(projectRoot, ".pi", "continue", `${encodeSessionIdForArtifactPath(sessionId)}.md`);
}

/**
 * Resolve the project root, package-owned continuation artifact path, and configured agent guide.
 * A guide whose real path leaves the project is only read when the operator's global opt-in allows
 * it; otherwise the context carries the reason instead of the content.
 */
export async function resolveProjectContext(
	pi: ExecApi,
	cwd: string,
	sessionId: string,
	configuredAgentGuidePath = DEFAULT_AGENT_GUIDE_PATH,
	allowAgentGuideOutsideProject = false,
): Promise<ResolvedProjectContext> {
	const projectRoot = await resolveProjectRoot(pi, cwd);
	const agentGuidePath = resolveAgentGuideTarget(projectRoot, configuredAgentGuidePath);
	const guide = await readContainedAgentGuide(projectRoot, agentGuidePath, allowAgentGuideOutsideProject);
	return {
		projectRoot,
		continuationArtifactPath: buildContinuationArtifactPath(projectRoot, sessionId),
		agentGuidePath,
		existingAgentGuide: guide.content,
		agentGuideReadRefusal: guide.refusal,
	};
}

async function resolveWriteTarget(path: string, options: NormalizedMarkdownWriteOptions): Promise<string> {
	if (options.containmentRoot === undefined) return path;
	const root = options.containmentRoot;
	if (options.refuseRedirectedPath) await assertUnredirectedPath(root, path, options.allowSymlinkedAncestor);
	const contained = await resolveContainedProjectPath(root, path);
	if (contained) {
		// The outside-project opt-in exists so a guide may live outside the repo; it never authorizes a
		// repo-committed link that aims the replacement at a different file inside the repo.
		if (!options.refuseRedirectedPath) await assertOutputFileIsNotSymlink(path);
		return contained;
	}
	// The refusal is judged on the resolved location, not the literal one, so a path that reaches
	// repo machinery only after symlinks and case folding is reported as the reserved path it is
	// instead of as an escape an outside-project opt-in could ever permit.
	const real = await resolveRealPath(path);
	const literal = resolve(path);
	if (pathHasRefusedSegment(real) || hasRefusedSegment(root, literal)) {
		throw new MarkdownWriteRefusedError(
			"reserved-path",
			`Resolved output path ${real} is inside repo-owned machinery that pi-continue never writes to.`,
		);
	}
	if (options.allowOutsideRoot) return real;
	// A package-owned path that only leaves the root through a parent directory the operator
	// symlinked on purpose is that same deliberate layout, not an escape the repo chose.
	if (options.allowSymlinkedAncestor && isInsideRoot(resolve(root), literal)) return real;
	throw new MarkdownWriteRefusedError(
		"outside-project",
		`Resolved output path ${real} is not a writable location inside ${root}.`,
	);
}

function contentDigest(content: string): string {
	return createHash("sha256").update(content, "utf8").digest("hex");
}

// Authorship is decided by what is in the file now, not by the path alone: a path this package
// wrote earlier holds someone else's content as soon as they edit it.
function isPackageAuthored(target: string, existingNormalized: string | undefined): boolean {
	if (existingNormalized === undefined) return false;
	if (packageWrittenDigests.get(target) === contentDigest(existingNormalized)) return true;
	return wasWrittenByPackage(target, existingNormalized);
}

async function writeResolvedTarget(target: string, normalized: string): Promise<void> {
	try {
		await writeFileAtomic(target, normalized, { noFollow: true });
	} catch (error) {
		if (error instanceof SymlinkDestinationError) {
			// A link that appeared at the destination after the checks above is the same refusal, so it
			// must not be reported as something the symlinked-directory opt-in could waive.
			throw new MarkdownWriteRefusedError("redirected-file", error.message);
		}
		throw error;
	}
}

/** Write a normalized Markdown file only when normalized content changes, inside the allowed root. */
export async function writeNormalizedMarkdownFile(
	path: string,
	content: string,
	options: NormalizedMarkdownWriteOptions = {},
): Promise<"updated" | "unchanged"> {
	const target = await resolveWriteTarget(path, options);
	const normalized = normalizeMarkdownContent(content);
	// The unchanged decision and the write share one queue slot, so a concurrent write cannot
	// make either caller report a status the file never had.
	return withMutationQueue(target, async () => {
		const existing = await readOptionalFile(target);
		const existingNormalized = existing === undefined ? undefined : normalizeMarkdownContent(existing);
		if (existingNormalized === normalized) return "unchanged";
		// Existence decides the confirmation, not readability: a file this package cannot read is
		// still content it did not write, so replacing it must be approved too. Content this package
		// wrote earlier, in this session or a previous one, is its own to replace.
		if (existsSync(target) && options.confirmOverwrite && !isPackageAuthored(target, existingNormalized)) {
			if (!(await options.confirmOverwrite(target))) {
				throw new MarkdownWriteRefusedError("overwrite-declined", `Existing ${basename(target)} was left unchanged without confirmation.`);
			}
		}
		await mkdir(dirname(target), { recursive: true });
		await writeResolvedTarget(target, normalized);
		packageWrittenDigests.set(target, contentDigest(normalized));
		// Only a target that can ever require approval needs durable provenance; recording the
		// per-session artifact paths too would evict the entries that answer that question.
		// Provenance is recorded even while approval is switched off, so the record stays
		// continuous and a later switch back to confirming does not prompt for this package's
		// own output.
		if (options.trackProvenance ?? options.confirmOverwrite !== undefined) await recordPackageWrite(target, normalized);
		return "updated";
	});
}

/** Keep generated continuation artifacts out of commits without touching repo-owned ignore files. */
export async function ensureContinuationArtifactIgnored(projectRoot: string, allowSymlinkedAncestor = false): Promise<void> {
	const target = join(projectRoot, ".pi", "continue", ".gitignore");
	try {
		// Same containment the brief itself gets, so the guard file follows the artifact into a
		// directory the operator deliberately symlinked instead of being skipped there.
		const resolved = await resolveWriteTarget(target, {
			containmentRoot: projectRoot,
			refuseRedirectedPath: true,
			allowSymlinkedAncestor,
		});
		if (existsSync(resolved)) return;
		await mkdir(dirname(resolved), { recursive: true });
		await writeFileAtomic(resolved, CONTINUATION_ARTIFACT_GITIGNORE, { noFollow: true });
	} catch {
		// A repo that refuses this guard file must not also lose the brief it guards.
	}
}
