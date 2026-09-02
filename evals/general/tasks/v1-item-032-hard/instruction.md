# PTY-driven interactive terminal harness (authentication state machine)

In `/app` there is an interactive terminal program `/app/app.py` called **VAULT**. It is a
three-phase **state machine**:

- **Phase A — authenticated login.** It first prints a colored `VAULT` banner, then prompts
  `user: ` and `pass: `. It will NOT advance until the username `admin` and password `abc123`
  are typed. Wrong credentials print `invalid user` / `invalid pass` and re-prompt.
- **Phase B (after login)** — it clears the screen (`ESC[2J`) and shows a `VAULT MENU` with the
  prompt `> `. It accepts:
  - `store <name>` — stores an item. While storing it shows a short **backspace animation**
    (it types `saving...` then overwrites it with backspaces before printing `stored: <name>`).
  - `remove <name>` — prints `removed: <name>`, or `unknown item: <name>` if absent.
  - `total` — prints `total: <N>`.
  - `report` — prints one ` - <name>` line per stored item, then `total: <N>`.
  - `quit` — prints `logged out` and exits.
  - anything else prints `unknown command: <cmd>`.

The program only accepts input when its current prompt has been printed and flushed, so a driver
must **model the state machine** and wait on each real prompt, tolerating **partial/timed reads**
(login prompts arrive before the menu; the `store` animation deliberately delays output).

## Your job

Write `/app/drive.py` that uses the standard `pty` module to run `/app/app.py` in a real terminal
and drives it end-to-end:

1. Wait for `user: `, send `admin`; wait for `pass: `, send `abc123`.
2. Wait for the `> ` prompt (post-login), then send these commands one at a time, waiting for the
   prompt between each: `store gold`, `store silver`, `total`, `report`, `remove silver`, `total`,
   `report`, `quit`.
3. **Model the terminal output**: maintain a byte-level renderer that (a) strips ANSI escape codes
   (SGR colours, and the `ESC[2J`/`ESC[H` clear-screen codes), (b) handles backspaces, and
   (c) handles carriage-return column resets so that the *visible* screen is reconstructed — the
   `saving...\b\b...stored: gold` animation must render as just `stored: gold` (the `saving...`
   text is overwritten away).
4. Write two files:
   - `/app/transcript.txt` — the plain visible rendered stream of the whole session (`\x1b`-free).
   - `/app/final.txt` — the state of the *visible screen at the moment the program exits* (i.e. the
     authenticated menu and the interaction after it, rendered with backspaces/overwrites applied).
5. Write `/app/log.json` with the key `commands` = the JSON array
   `["store gold","store silver","total","report","remove silver","total","report","quit"]`.

## Requirements

- `/app/drive.py` must depend only on the Python standard library (`pty`, `select`, `os`, `time`,
  `re`, `json`). No third-party packages.
- Run it so that `transcript.txt`, `final.txt`, and `log.json` are all produced.
- `final.txt` must contain no raw `\x1b` bytes and no literal leftover `saving` (the animation must
  be overwritten, not merely surviving next to the result).

The reward depends on the *rendered* user-visible screen, so get the escape/backspace handling right.