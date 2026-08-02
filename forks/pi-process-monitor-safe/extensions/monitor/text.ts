/**
 * Bounded text helpers. Local (dependency-free) so the runtime stays
 * hermetically testable; semantics mirror pi's tail truncation: keep the end
 * of the text, bounded by both line count and byte count.
 */

export interface TruncateTailOptions {
  maxLines: number;
  maxBytes: number;
}

export interface TruncateTailResult {
  content: string;
  truncated: boolean;
}

const TRUNCATION_MARKER = "… [earlier output truncated]";

/** Keep the tail of `text`, bounded to `maxLines` lines and `maxBytes` bytes. */
export function truncateTail(
  text: string,
  { maxLines, maxBytes }: TruncateTailOptions,
): TruncateTailResult {
  let truncated = false;
  let lines = text.split("\n");
  if (lines.length > maxLines) {
    lines = lines.slice(lines.length - maxLines);
    truncated = true;
  }
  let content = lines.join("\n");
  if (Buffer.byteLength(content, "utf8") > maxBytes) {
    content = tailBytes(content, maxBytes);
    truncated = true;
  }
  if (truncated) content = `${TRUNCATION_MARKER}\n${content}`;
  return { content, truncated };
}

/**
 * Bound an unterminated partial line.
 *
 * Under the cap the text is returned byte-for-byte, so ordinary output reaches the matcher
 * exactly as before — a partial line only gets rewritten once it is already too long to be
 * a real line. Past the cap, the text after the final carriage return is preferred: a
 * progress bar rewrites one line indefinitely, and that suffix is both what a terminal
 * would be showing and naturally small. The byte tail is the fallback for long output that
 * contains no carriage return at all.
 */
export function boundPartialLine(text: string, maxBytes: number): string {
  if (Buffer.byteLength(text, "utf8") <= maxBytes) return text;
  return tailBytes(text.slice(text.lastIndexOf("\r") + 1), maxBytes);
}

/** Keep at most the trailing `maxBytes` bytes of `text` (UTF-8 safe). */
export function tailBytes(text: string, maxBytes: number): string {
  const buf = Buffer.from(text, "utf8");
  if (buf.length <= maxBytes) return text;
  // Advance past any UTF-8 continuation bytes so we never split a character.
  let start = buf.length - maxBytes;
  while (start < buf.length && (buf[start]! & 0xc0) === 0x80) start++;
  return buf.subarray(start).toString("utf8");
}
