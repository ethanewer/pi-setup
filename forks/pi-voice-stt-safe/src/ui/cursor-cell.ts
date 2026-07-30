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

import { stripAnsi } from "./transcribing";

/** Pi's zero-width hardware-cursor marker. Kept as a literal so this module stays pure. */
export const CURSOR_MARKER = "\x1b_pi:c\x07";

const escapeRegExp = (value: string): string => value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

/** The marker plus the one reverse-video cell the editor draws as its cursor. */
export const CURSOR_CELL = new RegExp(`${escapeRegExp(CURSOR_MARKER)}\\x1b\\[7m[\\s\\S]*?\\x1b\\[0m`);

export { stripAnsi };

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

/** Styled text plus the number of columns it occupies, given separately because
 * measuring styled text on every frame is wasted work. */
export type Indicator = { text: string; width: number };

/**
 * Compose the cursor row: the indicator starts in the cursor's cell and runs over the
 * cells after it, with the rest of the line shifted back so the width never changes.
 *
 * `full` is used only when every cell it needs is blank — at the end of a line those are
 * the editor's padding, so it costs nothing, while mid-text there is nothing to write
 * over without hiding the user's own characters. In that case `minimal` is used instead,
 * which is a single cell. It is all or nothing on purpose: a partially drawn `[● recor`
 * would be worse than the bare dot.
 */
export const composeCursorLine = (line: string, full: Indicator, minimal: Indicator, width: number): string => {
	const parts = splitAtCursor(line);
	if (!parts) return line;

	const start = visibleWidth(parts.head);
	const fits = (indicator: Indicator) =>
		indicator.width > 0 &&
		start + indicator.width <= width &&
		(indicator.width === 1 || roomFor(parts.tail, indicator.width - 1));

	const chosen = fits(full) ? full : minimal;
	// The cursor's own cell is already gone with the run that was replaced; anything the
	// indicator needs beyond it comes out of the cells that follow.
	const consumed = Math.max(0, chosen.width - 1);
	const tail = consumed > 0 ? sliceByColumn(parts.tail, consumed, Math.max(0, width - start - chosen.width)) : parts.tail;
	return `${parts.head}${chosen.text}${tail}`;
};
