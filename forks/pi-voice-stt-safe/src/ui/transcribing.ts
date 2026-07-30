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

/** Braille spinner, the same set Pi uses for its own working indicator. */
export const SPINNER_FRAMES = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"] as const;

/** Stands in for the animated frame inside the placeholder's stored text. */
export const SPINNER_SENTINEL = "⠿";

export const PLACEHOLDER_PREFIX = `[${SPINNER_SENTINEL} `;
export const PLACEHOLDER_SUFFIX = "]";

/** The literal text inserted into the editor, or shown as a pending message. */
export const placeholderText = (label = "transcribing"): string =>
	`${PLACEHOLDER_PREFIX}${label}${PLACEHOLDER_SUFFIX}`;

/**
 * Swap the sentinel for the current frame in already-rendered lines. Braille cells are
 * single width, so the substitution cannot change the layout the editor computed — which
 * is the whole reason the sentinel is a character rather than a wider marker.
 */
export const animateRenderedLines = (lines: string[], frame: string, paint: (text: string) => string): string[] => {
	if (frame === SPINNER_SENTINEL) return lines;
	let touched = false;
	const out = lines.map((line) => {
		if (!line.includes(SPINNER_SENTINEL)) return line;
		touched = true;
		return line.split(SPINNER_SENTINEL).join(paint(frame));
	});
	return touched ? out : lines;
};

export const frameAt = (tick: number): string => SPINNER_FRAMES[tick % SPINNER_FRAMES.length] ?? SPINNER_FRAMES[0];

/**
 * Replace the first placeholder in `text` with `replacement`.
 *
 * Returns the original string when there is no placeholder left — the user may have
 * deleted it while the provider was working, and in that case the transcript has nowhere
 * to go and must not be appended blindly to whatever they typed instead.
 */
export const replacePlaceholder = (
	text: string,
	replacement: string,
): { text: string; replaced: boolean } => {
	const start = text.indexOf(PLACEHOLDER_PREFIX);
	if (start === -1) return { text, replaced: false };
	const end = text.indexOf(PLACEHOLDER_SUFFIX, start + PLACEHOLDER_PREFIX.length);
	if (end === -1) return { text, replaced: false };
	return {
		text: text.slice(0, start) + replacement + text.slice(end + PLACEHOLDER_SUFFIX.length),
		replaced: true,
	};
};

export const hasPlaceholder = (text: string): boolean => replacePlaceholder(text, "").replaced;
