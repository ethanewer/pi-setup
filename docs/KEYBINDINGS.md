# Keybindings that survive tmux

Default tmux forwards only *legacy* terminal encodings. A key that needs the Kitty
keyboard protocol, `modifyOtherKeys`, or CSI-u never arrives — the terminal either sends
nothing extra or sends the unmodified key. This file records which of Pi's defaults are
unreachable there, what this setup binds instead, and how it was determined.

Everything below was measured, not assumed, with `bin/pi-setup-keyprobe`, which decodes a
keypress through Pi's own `parseKey`/`matchesKey`.

## The terminal setting this depends on

On macOS, Option is not a modifier the terminal reports. It either composes a character or
acts as Meta:

| Setting | Option+P sends | Option+Enter sends |
|---|---|---|
| **Off** (default) | `π` (U+03C0) | usually plain `CR` — indistinguishable from Enter |
| **On** ("Use Option as Meta key" / "Esc+") | `ESC p` | `ESC CR` → Pi reads `alt+enter` |

So the Option bindings below need Meta **on**, for both the left and right Option key:

- **Terminal.app** — Settings → Profiles → Keyboard → *Use Option as Meta key*
- **iTerm2** — Settings → Profiles → Keys → set *Left Option* and *Right Option* to `Esc+`
- **Ghostty** — `macos-option-as-alt = true`
- **WezTerm** — `send_composed_key_when_left_alt_is_pressed = false` (and the right-alt twin)

Voice dictation works either way: the fork accepts a list of bindings and compares literal
characters as well as key ids, so `alt+p` and `π` are both bound.

## What this setup binds

`config/keybindings.json`, installed to `~/.pi/agent/keybindings.json` and the `p` profile.

| Action | Pi default | Bound here | Why |
|---|---|---|---|
| `tui.input.newLine` | `shift+enter`, `ctrl+j` | `alt+enter`, `ctrl+j` | `shift+enter` is unreachable: a legacy terminal sends `CR` for it, exactly as for Enter. `ctrl+j` (`0x0a`) is kept as the binding that needs no Meta at all. |
| `app.message.followUp` | `alt+enter` | `ctrl+alt+i` | Freed `alt+enter` for the newline. `ctrl+alt+i` **is** Option+Tab: the terminal sends `ESC TAB`, and Pi decodes `ESC` + `0x09` as `ctrl+alt+i`. Pi has no `alt+tab` key id at all. |
| `app.message.dequeue` | `alt+up` | `ctrl+alt+u` | Real conflict, not hygiene: Pi maps the legacy sequence `ESC p` to `alt+up`, so with Meta on, Option+P fired dictation *and* restored queued messages. |
| `app.model.cycleBackward` | `shift+ctrl+p` | `ctrl+alt+p` | `ctrl+shift+<letter>` is indistinguishable from `ctrl+<letter>` without CSI-u. |
| `app.tree.filter.cycleBackward` | `shift+ctrl+o` | `ctrl+alt+o` | Same reason. |

Voice dictation is in `stt.json`, not here: `"keybind": ["alt+p", "π"]`.

## Defaults that are already fine

Verified to decode correctly through tmux:

- `shift+tab` (`app.thinking.cycle`) — sends `ESC [ Z`, a standard back-tab, not a modified key.
- All `ctrl+<letter>` bindings — plain control codes.
- Modified arrows: `alt+left/right` (`ESC [ 1;3D/C`), `ctrl+left/right` (`1;5D/C`),
  `shift+up/down` (`1;2A/B`, used to scroll the `/btw` view). tmux forwards these.
- `alt+<letter>` bindings such as `alt+b`, `alt+f`, `alt+d`, `alt+y` — plain `ESC`-prefixed
  bytes once Meta is on.

## Left unbound rather than remapped

- `app.session.deleteNoninvasive` (`ctrl+backspace`) — macOS sends `0x7f` or `0x08` for it,
  which Pi already reads as plain `backspace`; there is no distinct sequence to bind. The
  session picker still deletes with `ctrl+d`.
- `tui.editor.undo` (`ctrl+-`) — Pi decodes `0x1f` as `ctrl+-`. Whether a terminal sends
  `0x1f` for that chord varies; check with `bin/pi-setup-keyprobe` before relying on it.

## Checking a key yourself

```bash
bin/pi-setup-keyprobe                 # press keys, see bytes and the id Pi matches
bin/pi-setup-keyprobe --decode 1b0d   # decode bytes without a terminal
```

Run it inside tmux and outside it. A binding is only safe where both agree, and only when
the reported id is the one you meant to bind. One caveat: Pi also negotiates the Kitty
keyboard protocol at startup, so on a terminal that supports it (Ghostty, Kitty, WezTerm,
iTerm2 3.5+) Pi can see richer sequences than the probe shows — but not through default
tmux, which does not forward them.
