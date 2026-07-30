/**
 * The `[⠏ transcribing]` placeholder.
 *
 * Transcription is no longer something the user waits on. The moment recording stops, a
 * placeholder takes the transcript's place — in the editor when the transcript is meant
 * to land there, or as a pending message in the transcript when it is being sent or
 * queued — and the user carries on typing. When the provider answers, the placeholder is
 * replaced by the real text; when it fails, by an error.
 *
 * The spinner animates without touching the editor's text. The placeholder holds a fixed
 * sentinel character and the frame is substituted in the *rendered* lines, so the editor's
 * own text and cursor never move under the user's hands, and a placeholder is still an
 * ordinary run of characters that can be spliced out by index.
 */

const ANSI = /\x1b\[[0-9;:]*[A-Za-z]|\x1b\][^\x07]*\x07|\x1b[_P^][^\x07]*\x07/g;

/** Visible characters only. Lives here because this module must not depend on pi-tui. */
export const stripAnsi = (text: string): string => text.replace(ANSI, "");

/** Braille spinner, the same set Pi uses for its own working indicator. */
export const SPINNER_FRAMES = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"] as const;

/** Stands in for the animated frame inside the placeholder's stored text. */
export const SPINNER_SENTINEL = "⠿";

export const PLACEHOLDER_PREFIX = `[${SPINNER_SENTINEL} `;
export const PLACEHOLDER_SUFFIX = "]";

/**
 * The literal text inserted into the editor, or shown as a pending message.
 *
 * `slot` distinguishes placeholders that are outstanding at the same time. Slot 1 reads
 * plainly; a second concurrent transcription is `[⠿ transcribing 2]`, and each delivery
 * replaces its own marker by exact text rather than "the first one in the string" — two
 * providers answering out of order used to swap their transcripts.
 */
export const placeholderText = (slot = 1): string =>
	`${PLACEHOLDER_PREFIX}transcribing${slot > 1 ? ` ${slot}` : ""}${PLACEHOLDER_SUFFIX}`;

/**
 * The bracket that opens or closes a placeholder run, ignoring the ones inside terminal
 * escapes. `ESC[7m` and `ESC[0m` both contain a `[`, and the editor renders its cursor as
 * exactly that — so a naive backwards search for `[` matched inside an escape whenever the
 * caret sat on the placeholder's first cells, sliced the escape in half, and pushed the
 * line past the terminal width. Pi treats an overlong line as fatal, so that crashed the
 * session mid-dictation.
 */
const bracketBefore = (line: string, from: number, bracket: string): number => {
	for (let i = from; i >= 0; i--) {
		if (line[i] !== bracket) continue;
		if (i > 0 && line[i - 1] === "\x1b") continue;
		return i;
	}
	return -1;
};

const bracketAfter = (line: string, from: number, bracket: string): number => {
	for (let i = from; i < line.length; i++) {
		if (line[i] !== bracket) continue;
		if (i > 0 && line[i - 1] === "\x1b") continue;
		return i;
	}
	return -1;
};

/** Foreground-colour escapes, so the editor's own text colour can be restored after ours. */
const FOREGROUND = /\x1b\[(?:38;[0-9;:]+|39|3[0-7]|9[0-7])m/g;

const foregroundBefore = (line: string, index: number): string => {
	let last = "";
	for (const match of line.slice(0, index).matchAll(FOREGROUND)) last = match[0];
	return last;
};

/**
 * Swap the sentinel for the current frame in already-rendered lines, and paint the whole
 * `[⠋ transcribing]` run so it reads as one dim block rather than as text the user typed.
 *
 * Only styling changes: braille cells are single width and the label is left alone, so
 * the substitution cannot alter the layout the editor computed. Whatever foreground was
 * in effect before the placeholder is re-emitted after it, so text typed alongside keeps
 * the editor's colour instead of falling back to the terminal default.
 */
export const animateRenderedLines = (lines: string[], frame: string, paint: (text: string) => string): string[] => {
	let touched = false;
	const out = lines.map((line) => {
		if (!line.includes(SPINNER_SENTINEL)) return line;
		touched = true;

		// Every run on the line, not just the first: two transcriptions can be outstanding
		// at once, and the second used to sit there showing its raw sentinel forever.
		let result = "";
		let cursor = 0;
		while (cursor <= line.length) {
			const at = line.indexOf(SPINNER_SENTINEL, cursor);
			if (at === -1) {
				result += line.slice(cursor);
				break;
			}
			const open = bracketBefore(line, at, PLACEHOLDER_PREFIX[0] ?? "[");
			const close = bracketAfter(line, at, PLACEHOLDER_SUFFIX);
			// A placeholder split across a wrap has no bracket on this line; colour the
			// frame alone rather than guessing where the run begins.
			// Anything that does not strip down to a real `[… ]` run is left to the
			// frame-only branch, which substitutes one single-width cell and so can never
			// change the line's width.
			const plausible =
				open !== -1 && close !== -1 && open >= cursor && stripAnsi(line.slice(open, close + 1)).startsWith("[");
			if (!plausible) {
				result += line.slice(cursor, at) + paint(frame) + foregroundBefore(line, at);
				cursor = at + SPINNER_SENTINEL.length;
				continue;
			}
			const body = line.slice(open, close + PLACEHOLDER_SUFFIX.length).split(SPINNER_SENTINEL).join(frame);
			result += line.slice(cursor, open) + paint(body) + foregroundBefore(line, open);
			cursor = close + PLACEHOLDER_SUFFIX.length;
		}
		return result;
	});
	return touched ? out : lines;
};

export const frameAt = (tick: number): string => SPINNER_FRAMES[tick % SPINNER_FRAMES.length] ?? SPINNER_FRAMES[0];

/**
 * Replace one specific placeholder with `replacement`.
 *
 * Returns the original string when that marker is no longer there — the user may have
 * deleted it while the provider was working, and in that case the transcript has nowhere
 * to go and must not be appended blindly to whatever they typed instead.
 */
export const replacePlaceholder = (
	text: string,
	replacement: string,
	marker: string = placeholderText(),
): { text: string; replaced: boolean } => {
	const start = text.indexOf(marker);
	if (start === -1) return { text, replaced: false };
	return { text: text.slice(0, start) + replacement + text.slice(start + marker.length), replaced: true };
};

export const hasPlaceholder = (text: string, marker: string = placeholderText()): boolean =>
	text.includes(marker);

/** The lowest slot not currently outstanding, so numbering stays as small as possible. */
export const nextFreeSlot = (taken: ReadonlySet<number>): number => {
	let slot = 1;
	while (taken.has(slot)) slot += 1;
	return slot;
};
