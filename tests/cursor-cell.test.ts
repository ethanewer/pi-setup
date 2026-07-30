import { describe, expect, mock, test } from "bun:test";
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const tuiEntry = join(
	process.env.BUN_INSTALL ?? join(homedir(), ".bun"),
	"install/global/node_modules/@earendil-works/pi-tui/dist/index.js",
);
const hasPiTui = existsSync(tuiEntry);
mock.module("@earendil-works/pi-tui", () =>
	hasPiTui ? require(tuiEntry) : { sliceByColumn: () => "", visibleWidth: (t: string) => t.length },
);

const { CURSOR_MARKER, composeCursorLine, roomFor, splitAtCursor, stripAnsi } = await import(
	"../forks/pi-voice-stt-safe/src/ui/cursor-cell"
);
const { visibleWidth } = hasPiTui ? require(tuiEntry) : { visibleWidth: (t: string) => t.length };

const DOT = "\x1b[31m●\x1b[39m";
const MINIMAL = { text: DOT, width: 1 };
/** `[● recording]` — grey brackets around the pulsing dot. */
const FULL = { text: `\x1b[90m[\x1b[39m${DOT}\x1b[90m recording]\x1b[39m`, width: "[● recording]".length };
/** The editor's cursor: marker, then one reverse-video cell. */
const cursorOn = (grapheme: string) => `${CURSOR_MARKER}\x1b[7m${grapheme}\x1b[0m`;
const pad = (line: string, width: number) => line + " ".repeat(Math.max(0, width - visibleWidth(line)));

describe.skipIf(!hasPiTui)("composeCursorLine", () => {
	test("takes the reverse-video cell with it, so nothing smears", () => {
		const line = pad(`hi ${cursorOn("a")}rest`, 40);
		const out = composeCursorLine(line, FULL, MINIMAL, 40);
		expect(out).not.toContain("\x1b[7m");
		expect(stripAnsi(out)).toContain("hi ●");
	});

	test("keeps the row exactly as wide, with and without the label", () => {
		const atEnd = pad(`typed ${cursorOn(" ")}`, 40);
		const inText = pad(`typed ${cursorOn("w")}ords here`, 40);
		expect(visibleWidth(composeCursorLine(atEnd, FULL, MINIMAL, 40))).toBe(40);
		expect(visibleWidth(composeCursorLine(inText, FULL, MINIMAL, 40))).toBe(40);
		expect(visibleWidth(composeCursorLine(atEnd, MINIMAL, MINIMAL, 40))).toBe(40);
	});

	test("writes the bracketed indicator into the padding after the cursor", () => {
		const out = composeCursorLine(pad(`typed ${cursorOn(" ")}`, 40), FULL, MINIMAL, 40);
		expect(stripAnsi(out)).toBe(pad("typed [● recording]", 40));
	});

	test("falls back to the bare dot rather than hide the user's own text", () => {
		const out = composeCursorLine(pad(`typed ${cursorOn("w")}ords here`, 40), FULL, MINIMAL, 40);
		expect(stripAnsi(out)).toBe(pad("typed ●ords here", 40));
		expect(stripAnsi(out)).not.toContain("recording");
	});

	test("omits the label when the row is too narrow for it", () => {
		const out = composeCursorLine(pad(`typed ${cursorOn(" ")}`, 12), FULL, MINIMAL, 12);
		expect(stripAnsi(out)).not.toContain("recording");
		expect(visibleWidth(out)).toBe(12);
	});

	test("leaves a line with no cursor alone", () => {
		const line = pad("no cursor here", 40);
		expect(composeCursorLine(line, FULL, MINIMAL, 40)).toBe(line);
	});

	test("falls back to dropping one column when the cursor is only a marker", () => {
		const line = pad(`typed ${CURSOR_MARKER}xyz`, 40);
		const out = composeCursorLine(line, FULL, MINIMAL, 40);
		expect(stripAnsi(out)).toContain("typed ●yz");
		expect(visibleWidth(out)).toBe(40);
	});
});

describe.skipIf(!hasPiTui)("helpers", () => {
	test("splitAtCursor reports nothing when there is no cursor", () => {
		expect(splitAtCursor("plain text")).toBeUndefined();
	});

	test("roomFor only accepts blank cells", () => {
		expect(roomFor("          rest", 10)).toBe(true);
		expect(roomFor("   text   ", 10)).toBe(false);
		expect(roomFor("  ", 10)).toBe(false);
	});

	test("stripAnsi keeps only what is visible", () => {
		expect(stripAnsi(`${DOT} recording`)).toBe("● recording");
	});
});
