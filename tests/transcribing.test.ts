import { describe, expect, test } from "bun:test";

import {
	animateRenderedLines,
	frameAt,
	hasPlaceholder,
	nextFreeSlot,
	placeholderText,
	replacePlaceholder,
	SPINNER_FRAMES,
	SPINNER_SENTINEL,
} from "../forks/pi-voice-stt-safe/src/ui/transcribing";

describe("placeholder", () => {
	test("carries the sentinel, not a live frame", () => {
		expect(placeholderText()).toBe(`[${SPINNER_SENTINEL} transcribing]`);
		expect(hasPlaceholder(`before ${placeholderText()} after`)).toBe(true);
		expect(hasPlaceholder("nothing here")).toBe(false);
	});

	test("is replaced in place, keeping what the user typed around it", () => {
		const text = `before ${placeholderText()} after`;
		expect(replacePlaceholder(text, "spoken words")).toEqual({
			text: "before spoken words after",
			replaced: true,
		});
	});

	test("reports when the user deleted it, so the transcript is not appended blindly", () => {
		expect(replacePlaceholder("user changed their mind", "spoken")).toEqual({
			text: "user changed their mind",
			replaced: false,
		});
	});

	test("two outstanding placeholders are addressed individually", () => {
		const first = placeholderText(1);
		const second = placeholderText(2);
		expect(second).toBe("[⠿ transcribing 2]");
		const text = `${first} and ${second}`;

		// Out of order on purpose: the second provider answering first must not take the
		// first block's spot, which is exactly what "replace the first placeholder" did.
		const b = replacePlaceholder(text, "SECOND", second);
		expect(b.text).toBe(`${first} and SECOND`);
		const a = replacePlaceholder(b.text, "FIRST", first);
		expect(a.text).toBe("FIRST and SECOND");
	});

	test("slot 1's marker does not match slot 2's block", () => {
		expect(hasPlaceholder(placeholderText(2), placeholderText(1))).toBe(false);
		expect(replacePlaceholder(placeholderText(2), "x", placeholderText(1)).replaced).toBe(false);
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
