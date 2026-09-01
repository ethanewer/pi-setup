# Dune Beacon — interactive terminal session

You are restoring a wind-stripped lighthouse: its old log books are empty, its
anchor deck is a maze of unlit corridors, its console still holds a half-forgotten
Vim session, and the tower's terminal game records the beacon's final lighting.
Your job is to produce **five** deliverables that together exercise several kinds
of interactive terminal work. Work **only** inside `/app`. Do not modify
`/app/server.py`, `/app/adventure.py`, or any file under `/app/data`,
`/app/instances`, or `/app/captured_layout.txt` — they are fixtures. You may add
any helper scripts you need (they are not graded), but the five deliverables
below must exist at exactly the listed paths and must be produced by **doing the
real work**, never by copying a precomputed answer.

Required deliverables:
  1. `/app/solve.py` — the maze solver (a real, general program).
  2. `/app/maps/reef.out`, `/app/maps/island.out`, `/app/maps/channel.out` —
     one reconstructed map per shipped maze instance.
  3. `/app/ending.txt` — the exact ending message of the lighthouse adventure.
  4. `/app/layout.vim` — canonical Vimscript that recreates a captured layout.
  5. `/app/macros.vim` — Vim macros under a total keystroke budget.

---

## Part 1 — drive the turn-based maze (solve.py + maps)

There is an interactive maze program `/app/server.py`. It loads a maze layout
and reads commands one JSON object per line on stdin; for every request it
prints one JSON response line to stdout (flushed). The program never prints the
maze; you can only learn it cell-by-cell by probing it.

Request (single or batched movement commands, the batch is applied
sequentially in order):
```
{"moves":["n","s","e","w",...]}
```
Response (one token per step, in the same order):
```
{"responses":["moved","wall","exit",...]}
```
Token meaning:
- `moved` — the step succeeded; you are now in that neighbouring cell.
- `wall` — the step was blocked (out of bounds or a wall); you stay put.
- `exit` — the step succeeded and you moved into the maze's exit cell.

You must track your own position yourself from these responses. On startup the
server prints a single banner line, e.g.
`READY ROWS=9 COLS=13 START=1,1`
so you know the grid size and your start cell. To stop it cleanly send
`{"bye":true}`.

`solve.py` must be runnable in **two modes** that share **one exploration
routine**:
```
python3 /app/solve.py --live <maze_file> <out_file>   # spawn server.py on pipes & explore interactively
python3 /app/solve.py --sim  <maze_file> <out_file>   # offline self-test: same routine, answers from local mock
```
The `--sim` mode reads the layout file directly (a mock server) so you can debug
your exploration routine against the **reference fixture** `/app/data/reference.txt`
and be confident it reaches **full coverage** before you trust it on the real
instances. In `--live` mode you must actually spawn `/app/server.py <maze_file>`
and drive it with movement commands — do not read the maze layout from disk to
fill the map.

**Output format** (same in both modes): one line per grid row. `#` = wall,
` ` (space) = passable interior cell, `S` = start cell, `E` = exit cell. The
layout contains a single connected passable region, so full coverage means your
probe of every reachable cell and every wall boundary recovers the whole map
exactly.

The shipped instances live at `/app/instances/reef.txt`, `/app/instances/island.txt`
and `/app/instances/channel.txt` (they have different shapes/sizes). Produce
`/app/maps/<name>.out` for each by running `--live`. Your solver will later be
re-run against **fresh hidden mazes it has never seen**, so write a general
algorithm (an exhaustive DFS/BFS that returns to branch points is the natural
fit), not something hard-coded to one instance.

`solve.py` must accept the exact `--live`/`--sim` interfaces above and write the
grid to the given `out_file` (UTF-8, no trailing blank lines).

---

## Part 2 — finish the lighthouse adventure (ending.txt)

`/app/adventure.py` is a small terminal text-adventure. Start it with
`python3 /app/adventure.py` and drive it **interactively** (use a pseudo-terminal,
e.g. Python's `pty` module or `script`). It prints room text and a `> ` prompt;
it reads commands from stdin. The game map:

```
courtyard --n--> gatehouse --e--> causeway --e--> pier --up--> isle --up--> tower --up--> gallery
     \--s--> stables                                              (cross the water only with the boat)
```
You can `take key` (stables), `open gate` (gatehouse, needs the key), `take
boat` (pier), then `up` to the isle, tower and gallery. In the **gallery**,
`light` triggers the ending of the game, which prints a distinctive one-line
**ending message**. In your captured transcript, extract exactly that line and
write it verbatim to `/app/ending.txt` (the line alone, with no leading/trailing
whitespace or `\r`).

Then **exit the game via its normal `quit` command** (not by killing the
process). Exiting normally is what tells the game to persist your journey to
the SQLite database at `/app/state/beacon.db` (a `players` row plus `events`
rows). Killing the process would write nothing, so always quit normally.

The exact ending message is *not* given in this prompt on purpose — you must
reach the end of the game yourself and capture the actual text it prints.

---

## Part 3 — recreate the captured Vim layout (layout.vim)

`/app/captured_layout.txt` describes a tab/window/buffer topology (2 tabs; tab 1
has 2 vertically-split windows showing buffers `deck.vim` and `cargo.txt`; tab 2
has 3 windows showing `sail.vim`, `rudder.vim`, `galley.txt`). For each of the
two tabs, the order of the buffers matters and both the visible window count per
tab and the whole set of tabs must match.

Write `/app/layout.vim` in canonical Vimscript that, when **sourced in a clean
headless Vim** (`vim -Nu NONE -n --not-a-term -S /app/layout.vim`), reproduces
that exact topology. Use plain commands such as `edit`, `tabnew`, `vnew`,
`split` (with `set splitbelow`/`set splitright` to fix ordering). The script
must be non-interactive and must not quit Vim when sourced. A verifier will
source it and compare the tab/window/buffer signature it observes against the
expected signature given in `captured_layout.txt`.

## Part 4 — Vim macros under a keystroke budget (macros.vim)

`/app/source_lines.txt` and `/app/target_lines.txt` are provided. Write
`/app/macros.vim` that defines macro **register `q`** as an editing sequence
which, applied once per line to `source_lines.txt`, transforms it into exactly
`target_lines.txt` (e.g. applied with `:%g/^/normal @q` or a comparable loop).
Keeping `source_lines.txt` open and OFF of any other buffer, applying `@q`
per line must reproduce `target_lines.txt` byte-for-byte.

**Keystroke budget:** the total combined length of every macro register you
define in `macros.vim` (sum of `len(@x)` for each register `x` you set) must be
**at most 150 keystrokes**. Compose the most economical editing sequence you
can — a recorded macro that repeats many literal keystrokes will blow the budget.
You may set extra registers if you wish, but they count toward the total.

---

## What will be checked
- `/app/solve.py` exists and is executable; running it via `--live` on shipped
  and on fresh hidden mazes reconstructs each map exactly.
- `/app/maps/{reef,island,channel}.out` exist and equal the true shipped maps.
- `/app/ending.txt` contains exactly the game's ending message.
- `/app/state/beacon.db` exists with a flushed player row (`reached_ending=1`)
  and gameplay `events` rows (proving you exited normally).
- `/app/layout.vim` sourced in a clean Vim reproduces the captured layout.
- `/app/macros.vim` macro(s) reproduce `target_lines.txt` from
  `source_lines.txt`, with total macro length at most 150.
