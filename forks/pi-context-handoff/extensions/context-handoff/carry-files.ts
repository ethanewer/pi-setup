/**
 * Carrying the accumulated file lists across a hook-produced compaction.
 *
 * Pi's compaction appends `<read-files>` and `<modified-files>` to every summary, and each
 * compaction seeds those lists from the previous compaction's entry — but only when that
 * entry was Pi's own. `extractFileOperations` in Pi's compaction.js guards the carry-over
 * with `!prevCompaction.fromHook`, and an entry returned from this hook is always marked
 * `fromHook: true`. So with this extension installed the lists silently restarted at every
 * boundary: after the second compaction the model no longer knew which files the run had
 * already read or changed.
 *
 * Merging them back in here is the only place it can be done, because Pi will not read our
 * entry's `details` for the same reason it will not read its lists.
 */

/** Shape of the compaction entries this reads. Only the fields that matter are declared. */
type CompactionEntryLike = {
	type?: string;
	details?: unknown;
};

type FileLists = { readFiles: string[]; modifiedFiles: string[] };

const READ_BLOCK = /\n*<read-files>\n[\s\S]*?\n<\/read-files>/g;
const MODIFIED_BLOCK = /\n*<modified-files>\n[\s\S]*?\n<\/modified-files>/g;

const asFileList = (value: unknown): string[] =>
	Array.isArray(value) ? value.filter((entry): entry is string => typeof entry === "string" && entry.length > 0) : [];

/** The lists on the most recent compaction in this branch, hook-produced or not. */
export const previousFileLists = (entries: readonly CompactionEntryLike[] | undefined): FileLists => {
	if (!Array.isArray(entries)) return { readFiles: [], modifiedFiles: [] };
	for (let i = entries.length - 1; i >= 0; i--) {
		const entry = entries[i];
		if (entry?.type !== "compaction") continue;
		const details = (entry.details ?? {}) as { readFiles?: unknown; modifiedFiles?: unknown };
		return { readFiles: asFileList(details.readFiles), modifiedFiles: asFileList(details.modifiedFiles) };
	}
	return { readFiles: [], modifiedFiles: [] };
};

/** Mirrors Pi's computeFileLists: a file that was modified is not also listed as read. */
export const mergeFileLists = (previous: FileLists, current: FileLists): FileLists => {
	const modified = new Set([...previous.modifiedFiles, ...current.modifiedFiles]);
	const read = new Set([...previous.readFiles, ...current.readFiles].filter((file) => !modified.has(file)));
	return { readFiles: [...read].sort(), modifiedFiles: [...modified].sort() };
};

/** Mirrors Pi's formatFileOperations, so a carried summary is byte-identical in shape. */
export const formatFileLists = ({ readFiles, modifiedFiles }: FileLists): string => {
	const sections: string[] = [];
	if (readFiles.length > 0) sections.push(`<read-files>\n${readFiles.join("\n")}\n</read-files>`);
	if (modifiedFiles.length > 0) sections.push(`<modified-files>\n${modifiedFiles.join("\n")}\n</modified-files>`);
	return sections.length === 0 ? "" : `\n\n${sections.join("\n\n")}`;
};

export const stripFileLists = (summary: string): string =>
	summary.replace(READ_BLOCK, "").replace(MODIFIED_BLOCK, "").trimEnd();

/**
 * Rewrite a freshly produced compaction so its file lists include everything the run has
 * touched, not just this window. Returns the input unchanged when there is nothing to
 * carry, so the common first-compaction case is untouched.
 */
export const carryFileLists = <T extends { summary: string; details?: unknown }>(
	compaction: T,
	entries: readonly CompactionEntryLike[] | undefined,
): T => {
	const previous = previousFileLists(entries);
	if (previous.readFiles.length === 0 && previous.modifiedFiles.length === 0) return compaction;

	const details = (compaction.details ?? {}) as { readFiles?: unknown; modifiedFiles?: unknown };
	const current = { readFiles: asFileList(details.readFiles), modifiedFiles: asFileList(details.modifiedFiles) };
	const merged = mergeFileLists(previous, current);

	return {
		...compaction,
		summary: `${stripFileLists(compaction.summary)}${formatFileLists(merged)}`,
		details: { ...details, ...merged },
	};
};
