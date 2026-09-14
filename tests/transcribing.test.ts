import { describe, expect, test } from "bun:test";

import {
	animateRenderedLines,
	frameAt,
	nextFreeSlot,
	placeholderText,
	SPINNER_FRAMES,
	SPINNER_SENTINEL,
} from "../forks/pi-voice-stt-safe/src/ui/transcribing";

describe("placeholder", () => {
	test("carries the sentinel, not a live frame, and slots number the concurrent ones", () => {
		expect(placeholderText()).toBe(`[${SPINNER_SENTINEL} transcribing]`);
		// Slot 2's marker is a different string from slot 1's, so two outstanding
		// transcriptions can be told apart by exact text.
		expect(placeholderText(2)).toBe("[⠿ transcribing 2]");
	});
});

describe("slots", () => {
	test("reuses the lowest number that is free", () => {
		expect(nextFreeSlot(new Set())).toBe(1);
		expect(nextFreeSlot(new Set([1]))).toBe(2);
		expect(nextFreeSlot(new Set([1, 2]))).toBe(3);
		// A finished transcription frees its slot, so numbering stays small.
		expect(nextFreeSlot(new Set([2]))).toBe(1);
	});
});

describe("animation", () => {
	test("substitutes the frame without changing the line's width", () => {
		const line = `some ${placeholderText()} text`;
		const [animated] = animateRenderedLines([line], "⠙", (t) => t);
		expect(animated).toBe("some [⠙ transcribing] text");
		expect(animated?.length).toBe(line.length);
	});

	test("paints the whole run, brackets and label included", () => {
		const [animated] = animateRenderedLines([placeholderText()], "⠙", (t) => `<${t}>`);
		expect(animated).toBe("<[⠙ transcribing]>");
	});

	test("animates every placeholder on the line, not just the first", () => {
		const line = `${placeholderText(1)} gap ${placeholderText(2)}`;
		const [animated] = animateRenderedLines([line], "⠙", (t) => t);
		expect(animated).toBe("[⠙ transcribing] gap [⠙ transcribing 2]");
		expect(animated).not.toContain(SPINNER_SENTINEL);
	});

	test("animates a numbered placeholder too", () => {
		const [animated] = animateRenderedLines([placeholderText(2)], "⠙", (t) => `<${t}>`);
		expect(animated).toBe("<[⠙ transcribing 2]>");
	});

	test("restores the foreground that was in effect before it", () => {
		const line = `\x1b[38;2;1;2;3mtyped ${placeholderText()} more`;
		const [animated] = animateRenderedLines([line], "⠙", (t) => `\x1b[90m${t}\x1b[39m`);
		expect(animated).toBe("\x1b[38;2;1;2;3mtyped \x1b[90m[⠙ transcribing]\x1b[39m\x1b[38;2;1;2;3m more");
	});

	test("colours the frame alone when the run is split across a wrap", () => {
		// The sentinel wrapped onto this line but its opening bracket did not, so there is
		// no run to paint — only the frame is substituted.
		const [wrapped] = animateRenderedLines([`${SPINNER_SENTINEL} transcribing] tail`], "⠙", (t) => `<${t}>`);
		expect(wrapped).toBe("<⠙> transcribing] tail");
	});

	test("leaves lines without a placeholder untouched", () => {
		const lines = ["plain", "also plain"];
		expect(animateRenderedLines(lines, "⠙", (t) => t)).toBe(lines);
	});

	test("cycles through every frame", () => {
		const seen = new Set(Array.from({ length: SPINNER_FRAMES.length }, (_, i) => frameAt(i)));
		expect(seen.size).toBe(SPINNER_FRAMES.length);
		expect(frameAt(SPINNER_FRAMES.length)).toBe(frameAt(0));
	});
});
