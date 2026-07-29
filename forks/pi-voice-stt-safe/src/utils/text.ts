export const formatError = (error: unknown): string => {
  if (error instanceof Error) return error.message;
  if (typeof error === "string") return error;
  return String(error);
};

/**
 * Placeholder the pi editor leaves in its raw text for a large paste, e.g.
 * `[paste #1 +90 lines]` or `[paste #2 1234 chars]`. Kept looser than the
 * editor's own matcher (pi-tui PASTE_MARKER_REGEX) so a reworded suffix still
 * counts: the caller uses this to avoid writing a marker back through
 * setEditorText, which clears the map the marker would have expanded from.
 */
const PASTE_MARKER = /\[paste(?:d text)? #\d+/i;

export const containsPasteMarker = (value: string): boolean => PASTE_MARKER.test(value);

export const truncate = (value: string, length = 360): string => {
  if (value.length <= length) return value;
  return `${value.slice(0, length)}…`;
};
