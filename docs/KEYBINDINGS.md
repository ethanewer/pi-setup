# Keybindings that survive tmux

There are **two** encodings in play, and a binding has to cover both.

Modern terminals (Ghostty, Kitty, WezTerm, iTerm2 3.5+) negotiate the **Kitty keyboard
protocol** with Pi and then report modifiers explicitly: Option+Tab arrives as
`ESC [ 9;3u`, which Pi reads as `alt+tab`. Terminal.app has no such support, and default
tmux does not forward the protocol even when the outer terminal has it — so the same
chord arrives as the **legacy** `ESC TAB`, which Pi reads as `ctrl+alt+i`. Keys that only
exist in the protocol, `shift+enter` among them, simply do not arrive in legacy mode.

So each action below is bound to *both* forms. The one that cannot be produced is inert,
which costs nothing.

Everything here was measured, not assumed, with `bin/pi-setup-keyprobe`, which negotiates
the protocol the way Pi does and decodes each keypress through Pi's own
`parseKey`/`matchesKey`.

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
characters as well as key ids, so `alt+p` and `π` are both bound — including the `ESC [ 960 u`
form a Kitty-protocol terminal uses to report a composed `π`.

## What this setup binds

`config/keybindings.json`, installed to `~/.pi/agent/keybindings.json` and the `p` profile.

| Action | Pi default | Bound here | Why |
|---|---|---|---|
| `tui.input.newLine` | `shift+enter`, `ctrl+j` | `alt+enter`, `shift+enter`, `ctrl+j` | Option+Enter is `alt+enter` in both modes. `shift+enter` is kept because it *does* work under the protocol, and because a Kitty-mode terminal reports `ESC CR` as `shift+enter`. `ctrl+j` (`0x0a`) needs no Meta and no protocol at all. |
| `app.message.followUp` | `alt+enter` | `alt+tab`, `ctrl+alt+i` | Freed `alt+enter` for the newline. Option+Tab is `alt+tab` under the protocol and `ctrl+alt+i` without it — Pi decodes legacy `ESC` + `0x09` as ctrl+alt+i, since `0x09` is in the control range. Binding only one of the two is why this silently did nothing in Ghostty at first. |
| `app.message.dequeue` | `alt+up` | `ctrl+alt+u` | Real conflict, not hygiene: Pi maps the legacy sequence `ESC p` to `alt+up`, so with Meta on, Option+P fired dictation *and* restored queued messages. |
| `app.model.cycleBackward` | `shift+ctrl+p` | `ctrl+alt+p` | `ctrl+shift+<letter>` is indistinguishable from `ctrl+<letter>` without CSI-u. |
| `app.tree.filter.cycleBackward` | `shift+ctrl+o` | `ctrl+alt+o` | Same reason. |

Voice dictation is in `stt.json`, not here: `"keybind": ["alt+p", "π"]`. The fork also
registers it as an extension shortcut so `/hotkeys` lists it — the editor sees the key
before Pi's shortcut dispatch, so that registration is for discoverability, and its
description carries the keys that only apply while recording.

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

Run it inside tmux and outside it: the header line tells you which mode you are in, and
the same terminal will usually report differently in each. A binding is safe when it
covers whatever the reported id is in both.
