import { describe, expect, test } from "bun:test";

import {
	animateRenderedLines,
	frameAt,
	hasPlaceholder,
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

	test("replaces only the first of two outstanding placeholders", () => {
		const text = `${placeholderText()} and ${placeholderText()}`;
		const once = replacePlaceholder(text, "first");
		expect(once.text).toBe(`first and ${placeholderText()}`);
		expect(replacePlaceholder(once.text, "second").text).toBe("first and second");
	});

	test("a custom label still round-trips", () => {
		const text = placeholderText("transcribing, will queue");
		expect(hasPlaceholder(text)).toBe(true);
		expect(replacePlaceholder(text, "x").text).toBe("x");
	});
});

describe("animation", () => {
	test("substitutes the frame without changing the line's width", () => {
		const line = `some ${placeholderText()} text`;
		const [animated] = animateRenderedLines([line], "⠙", (t) => t);
		expect(animated).toBe("some [⠙ transcribing] text");
		expect(animated?.length).toBe(line.length);
	});

	test("leaves lines without a placeholder untouched", () => {
		const lines = ["plain", "also plain"];
		expect(animateRenderedLines(lines, "⠙", (t) => t)).toBe(lines);
	});

	test("paints only the frame, so surrounding styling is preserved", () => {
		const [animated] = animateRenderedLines([placeholderText()], "⠙", (t) => `<${t}>`);
		expect(animated).toBe("[<⠙> transcribing]");
	});

	test("cycles through every frame", () => {
		const seen = new Set(Array.from({ length: SPINNER_FRAMES.length }, (_, i) => frameAt(i)));
		expect(seen.size).toBe(SPINNER_FRAMES.length);
		expect(frameAt(SPINNER_FRAMES.length)).toBe(frameAt(0));
	});
});
