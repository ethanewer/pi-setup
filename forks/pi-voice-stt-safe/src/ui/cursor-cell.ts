/**
 * Drawing the recording indicator into the editor's cursor cell.
 *
 * The editor renders its cursor as `CURSOR_MARKER` followed by one reverse-video cell:
 * `ESC[7m` + the grapheme under the cursor + `ESC[0m`. Replacing that whole run keeps the
 * row exactly as wide — which matters, because Pi kills the session when a rendered line
 * overflows the terminal — and takes the `ESC[7m` with it, which is what stops the
 * highlight smearing across the rest of the row.
 *
 * The " recording" label is written into the cells that follow, and only when those cells
 * are blank. At the end of a line they are the editor's padding, so the label costs
 * nothing; in the middle of typed text there is nothing to overwrite without hiding the
 * user's own characters, so the dot appears alone.
 */

import { sliceByColumn, visibleWidth } from "@earendil-works/pi-tui";

/** Pi's zero-width hardware-cursor marker. Kept as a literal so this module stays pure. */
export const CURSOR_MARKER = "\x1b_pi:c\x07";

const escapeRegExp = (value: string): string => value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

/** The marker plus the one reverse-video cell the editor draws as its cursor. */
export const CURSOR_CELL = new RegExp(`${escapeRegExp(CURSOR_MARKER)}\\x1b\\[7m[\\s\\S]*?\\x1b\\[0m`);

const ANSI = /\x1b\[[0-9;:]*[A-Za-z]|\x1b\][^\x07]*\x07|\x1b[_P^][^\x07]*\x07/g;

/** Visible characters only, for deciding whether a region is safe to write over. */
export const stripAnsi = (text: string): string => text.replace(ANSI, "");

export type CursorLineParts = {
	/** Everything before the cursor. */
	head: string;
	/** Everything after the cursor cell. */
	tail: string;
};

export const splitAtCursor = (line: string): CursorLineParts | undefined => {
	const match = CURSOR_CELL.exec(line);
	if (match) {
		return { head: line.slice(0, match.index), tail: line.slice(match.index + match[0].length) };
	}
	// Cursor rendering that does not match the expected shape: fall back to the marker
	// alone and drop one column, so the dot still replaces rather than widens.
	const marker = line.indexOf(CURSOR_MARKER);
	if (marker === -1) return undefined;
	const rest = line.slice(marker + CURSOR_MARKER.length);
	// `ESC[27m` cancels reverse video in case the dropped cell had turned it on.
	return { head: line.slice(0, marker), tail: `\x1b[27m${sliceByColumn(rest, 1, visibleWidth(rest))}` };
};

/** True when the next `columns` cells hold nothing but blanks. */
export const roomFor = (tail: string, columns: number): boolean => {
	const region = stripAnsi(sliceByColumn(tail, 0, columns));
	return region.length >= columns && region.trim().length === 0;
};

/**
 * Compose the cursor row: `dot` in the cursor's cell, then `label` over the blank cells
 * that follow it, with the rest of the line shifted back so the width never changes.
 *
 * `dot` and `label` are already styled; their visible widths are given separately because
 * measuring styled text at every frame is wasted work.
 */
export const composeCursorLine = (
	line: string,
	dot: string,
	label: { text: string; width: number } | undefined,
	width: number,
): string => {
	const parts = splitAtCursor(line);
	if (!parts) return line;

	const used = visibleWidth(parts.head) + 1;
	const showLabel = label && label.width > 0 && used + label.width <= width && roomFor(parts.tail, label.width);
	const tail = showLabel ? sliceByColumn(parts.tail, label.width, Math.max(0, width - used - label.width)) : parts.tail;
	return `${parts.head}${dot}${showLabel ? label.text : ""}${tail}`;
};
