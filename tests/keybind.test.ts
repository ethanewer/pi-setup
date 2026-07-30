import { describe, expect, mock, test } from "bun:test";
import { homedir } from "node:os";
import { existsSync } from "node:fs";
import { join } from "node:path";

// keybind.ts imports matchesKey from @earendil-works/pi-tui, which Pi supplies at
// runtime and which is not a dependency of this repository. Point the specifier at the
// installed copy so the matcher is tested against the real implementation; when Pi is not
// installed, the matcher tests skip and the pure ones still run.
const tuiEntry = join(
	process.env.BUN_INSTALL ?? join(homedir(), ".bun"),
	"install/global/node_modules/@earendil-works/pi-tui/dist/index.js",
);
const hasPiTui = existsSync(tuiEntry);
if (hasPiTui) {
	mock.module("@earendil-works/pi-tui", () => require(tuiEntry));
} else {
	mock.module("@earendil-works/pi-tui", () => ({ matchesKey: () => false }));
}

const { DEFAULT_KEYBINDS, describeKeybinds, matchesAnyKeybind, parseKeybinds } = await import(
	"../forks/pi-voice-stt-safe/src/core/keybind"
);

describe("parseKeybinds", () => {
	test("accepts an array", () => {
		expect(parseKeybinds(["alt+p", "π"])).toEqual(["alt+p", "π"]);
	});

	test("accepts a comma-separated string, for PI_STT_KEYBIND", () => {
		expect(parseKeybinds("alt+p, π")).toEqual(["alt+p", "π"]);
	});

	test("accepts a plain string", () => {
		expect(parseKeybinds("ctrl+r")).toEqual(["ctrl+r"]);
	});

	test("drops blanks and duplicates", () => {
		expect(parseKeybinds(["alt+p", "", "  ", "alt+p"])).toEqual(["alt+p"]);
	});

	test("falls back when the value is unusable", () => {
		expect(parseKeybinds(undefined)).toEqual([...DEFAULT_KEYBINDS]);
		expect(parseKeybinds(42)).toEqual([...DEFAULT_KEYBINDS]);
		expect(parseKeybinds([])).toEqual([...DEFAULT_KEYBINDS]);
		expect(parseKeybinds("   ", ["alt+p"])).toEqual(["alt+p"]);
	});
});

describe("matchesAnyKeybind", () => {
	const binds = ["alt+p", "π"];

	test.skipIf(!hasPiTui)("matches a Pi key id, from the bytes a Meta terminal sends", () => {
		expect(matchesAnyKeybind("\x1bp", binds)).toBe(true);
	});

	test("matches a literal character, which Pi's matchesKey cannot express", () => {
		expect(matchesAnyKeybind("π", binds)).toBe(true);
	});

	test.skipIf(!hasPiTui)("does not match anything else", () => {
		expect(matchesAnyKeybind("p", binds)).toBe(false);
		expect(matchesAnyKeybind("\x1bq", binds)).toBe(false);
		expect(matchesAnyKeybind("\r", binds)).toBe(false);
	});

	test("an unknown key id costs only that binding", () => {
		expect(matchesAnyKeybind("π", ["not-a-key", "π"])).toBe(true);
		expect(matchesAnyKeybind("x", ["not-a-key"])).toBe(false);
	});

	test("an empty list matches nothing", () => {
		expect(matchesAnyKeybind("π", [])).toBe(false);
	});
});

describe("describeKeybinds", () => {
	test("reads as a list in the editor label", () => {
		expect(describeKeybinds(["alt+p", "π"])).toBe("alt+p / π");
	});
});
