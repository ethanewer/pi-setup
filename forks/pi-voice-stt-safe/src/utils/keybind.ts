/**
 * Raw-key helpers for the profile menu shortcut.
 *
 * pi-tui's key parser decodes Kitty CSI-u modifier values with an off-by-one
 * (`modValue - 1`), so a real `ctrl+shift+r` (Kitty modifier 5, `\x1b[114;5u`)
 * is misread as plain `ctrl+r`. That makes `ctrl+shift+<letter>` impossible to
 * match through the normal key pipeline. As a workaround the extension matches
 * the raw terminal sequence itself for `ctrl+shift+<letter>` keybinds, which
 * works on terminals that forward the Kitty keyboard protocol (iTerm2, WezTerm,
 * kitty; inside tmux it needs `set -s extended-keys on`).
 */

/**
 * Build a regex that matches the raw Kitty CSI-u encoding of
 * `ctrl+shift+<letter>` (modifier 5, semicolon form). Returns undefined when
 * the keybind is not a ctrl+shift+letter combo (those work through the normal
 * parser, e.g. `alt+r`).
 */
export const kittyCtrlShiftLetterRegex = (keybind: string): RegExp | undefined => {
  const parts = keybind.toLowerCase().split("+");
  if (parts.length !== 3 || !parts.includes("ctrl") || !parts.includes("shift")) return undefined;
  const letter = parts.find((part) => /^[a-z]$/.test(part));
  if (!letter) return undefined;
  const lower = letter.charCodeAt(0);
  const upper = lower - 32;
  return new RegExp(`^\\x1b\\[(?:${lower}|${upper});5(?::\\d+)?u$`);
};
