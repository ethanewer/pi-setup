import { randomUUID } from "node:crypto";
import { constants } from "node:fs";
import { lstat, open, rename, rm, stat } from "node:fs/promises";
import { basename, dirname, join } from "node:path";

// O_EXCL already refuses an existing symlink; O_NOFOLLOW is added where the platform defines it
// so the refusal does not depend on that side effect alone.
const EXCLUSIVE_CREATE_FLAGS = constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | (constants.O_NOFOLLOW ?? 0);

export interface AtomicWriteOptions {
	/** Refuse a destination that is a symlink instead of writing through it. */
	noFollow?: boolean;
}

/** Raised when the write destination is a symlink and the caller refuses to follow one. */
export class SymlinkDestinationError extends Error {
	readonly path: string;

	constructor(path: string) {
		super(`Refusing to write through the symlink at ${path}.`);
		this.path = path;
	}
}

function hasErrorCode(error: unknown, ...codes: string[]): boolean {
	if (typeof error !== "object" || error === null) return false;
	const code = (error as { code?: unknown }).code;
	return typeof code === "string" && codes.includes(code);
}

async function existingFileMode(path: string): Promise<number | undefined> {
	try {
		return (await stat(path)).mode & 0o777;
	} catch {
		return undefined;
	}
}

async function isSymbolicLink(path: string): Promise<boolean> {
	try {
		return (await lstat(path)).isSymbolicLink();
	} catch {
		return false;
	}
}

// Creating the destination exclusively leaves no window in which a symlink planted at that name
// could be followed; a name that already exists falls through to the replace-by-rename path.
async function createFileExclusive(path: string, content: string): Promise<boolean> {
	let handle: Awaited<ReturnType<typeof open>>;
	try {
		handle = await open(path, EXCLUSIVE_CREATE_FLAGS);
	} catch (error) {
		if (hasErrorCode(error, "EEXIST", "ELOOP")) return false;
		throw error;
	}
	try {
		await handle.writeFile(content, "utf8");
		await handle.sync();
	} finally {
		await handle.close();
	}
	return true;
}

/** Write a file through a temp file and rename so an interrupted write cannot truncate the target. */
export async function writeFileAtomic(path: string, content: string, options: AtomicWriteOptions = {}): Promise<void> {
	if (options.noFollow) {
		if (await isSymbolicLink(path)) throw new SymlinkDestinationError(path);
		if (await createFileExclusive(path, content)) return;
		// A link planted after that check still cannot redirect the content: the rename below
		// replaces the destination name itself instead of writing through what it points at.
		if (await isSymbolicLink(path)) throw new SymlinkDestinationError(path);
	}
	const tempPath = join(dirname(path), `.${basename(path)}.${randomUUID()}.tmp`);
	const mode = await existingFileMode(path);
	try {
		const handle = await open(tempPath, EXCLUSIVE_CREATE_FLAGS);
		try {
			await handle.writeFile(content, "utf8");
			if (mode !== undefined) await handle.chmod(mode);
			await handle.sync();
		} finally {
			await handle.close();
		}
		await rename(tempPath, path);
	} catch (error) {
		await rm(tempPath, { force: true }).catch(() => undefined);
		throw error;
	}
}
