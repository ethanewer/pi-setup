import { matchesKey, type KeyId } from "@earendil-works/pi-tui";

/**
 * Voice dictation can be bound to more than one key, because on macOS the same physical
 * chord produces different bytes depending on a terminal setting: with "Use Option as
 * Meta key" off, Option+P sends the composed character `π`; with it on, the same chord
 * sends `ESC p`, which Pi reads as `alt+p`. Binding both makes the key work either way,
 * and across terminals that disagree about it.
 *
 * Pi's own keybindings cannot express this: `matchesKey` has no notion of a literal
 * character, and returns false even for `matchesKey("π", "π")`.
 */

export const DEFAULT_KEYBINDS = ["ctrl+r"] as const;

/** Accepts a string, a comma-separated string, or an array. Never throws. */
export const parseKeybinds = (value: unknown, fallback: readonly string[] = DEFAULT_KEYBINDS): string[] => {
	const out: string[] = [];
	const push = (candidate: unknown): void => {
		if (typeof candidate !== "string") return;
		const trimmed = candidate.trim();
		if (trimmed.length > 0 && !out.includes(trimmed)) out.push(trimmed);
	};

	if (Array.isArray(value)) {
		for (const entry of value) push(entry);
	} else if (typeof value === "string") {
		// A comma-separated string keeps PI_STT_KEYBIND="alt+p,π" working. A literal
		// comma cannot be bound this way; use the array form in stt.json for that.
		for (const entry of value.split(",")) push(entry);
	}

	return out.length > 0 ? out : [...fallback];
};

/**
 * True when the raw terminal bytes are one of the bound keys.
 *
 * Each binding is tried as a literal first, then as a Pi key id. An unknown id makes
 * `matchesKey` return false rather than throw, so a typo in the config costs that one
 * binding and nothing else.
 */
export const matchesAnyKeybind = (data: string, keybinds: readonly string[]): boolean => {
	for (const keybind of keybinds) {
		if (keybind.length === 0) continue;
		if (data === keybind) return true;
		try {
			if (matchesKey(data, keybind as KeyId)) return true;
		} catch {
			// Not a key id Pi knows. The literal comparison above was its only chance.
		}
	}
	return false;
};

/** How the binding is shown in the editor's right-hand label and in `/stt status`. */
export const describeKeybinds = (keybinds: readonly string[]): string => keybinds.join(" / ");
