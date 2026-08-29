# zephyr-gasket — Maze Explorer + Chess Coach

Two halves of one benchmark, both pure deterministic Python and both checked
by an automated verifier:

1. an **unknown-maze explorer** that fully maps a maze it can never see up
   front (by walking it and then reporting the full layout plus a legal route
   to an exit), and
2. a **chess mate-in-1 finder** that lists every checkmate move available to a
   given side to move.

You ship one executable program, `/app/solve.py`, and run it to produce
`/app/answer.json`.

## Deliverables (exactly what is checked)

- `/app/solve.py` — a Python 3 program implementing the four CLIs below. It is
  **run on the visible fixtures and again on unseen, hidden mazes and hidden
  chess positions**, so it must be a real, general algorithm, not a lookup
  table.
- `/app/answer.json` — produced by `python3 /app/solve.py` with no arguments.
  Valid JSON with the schema given below.

Do not modify anything under `/app/mazeapi.py`, `/app/reference_maze.py`, or
`/app/games/`.

---

## Part A — the maze explorer (maze side)

The maze lives in `/app/mazeapi.py`, which exposes the class `mazeapi.Maze`.
The maze is **unknown**: you only see a small local window from wherever your
pawn stands, and you can only move a pawn one cell at a time through open
passages — like exploring a real maze. You must visit every reachable cell,
record the open passages everywhere, and finally return a legal walk from the
start to the exit.

### Maze API

```python
import mazeapi
m = mazeapi.Maze("some-maze-id")     # each id -> a different deterministic maze
rows, cols = m.dimensions()          # each is between 6 and 9
start      = list(m.start)           # [row, col] you begin there (always row 0)
pos        = m.position()            # (row, col) your current cell

m.peek(direction) -> bool            # is the passage OPEN in this direction
                                     #   from the cell you stand on now?
m.move(direction) -> bool            # move one step; True if moved (passage
                                     #   was open), False if a wall is there
m.at_exit() -> bool                  # True when your pawn is on the exit cell
m.budget() -> int                    # moves still remaining before fail
```

Directions are the letters `N` (row-1), `S` (row+1), `E` (col+1), `W` (col-1),
with row 0 the top and col 0 the left. Passages are symmetric: if `(r,c)` has an
open `E` passage then `(r,c+1)` has an open `W` passage.

- `peek` and `move` only describe **the cell your pawn currently stands on**.
  That is what makes this a real navigation problem: to know a neighbor you
  must first walk to it.
- Every cell of the grid is reachable from the start, and the exit is always
  reachable by open passages — the "maze" spans the whole `rows x cols` grid.
- Some passages were opened randomly, so mazes contain **cycles** and **dead
  ends**; never assume a simple single-corridor path.
- There is a per-instance **move budget** (the api raises `RuntimeError` when
  it is exceeded). A complete DFS with backtracking stays comfortably inside;
  do not waste moves re-exploring hopelessly.
- `m.move` raises `ValueError` for an invalid direction string; do not rely on
  the message text, just normalize before passing it.

### Maze result schema

`python3 /app/solve.py maze <maze_id> <out.json>` writes:

```json
{
  "start": "0,0",
  "rows": 7,
  "cols": 9,
  "map": { "1,3": [1, 1, 0, 1], "1,4": [1, 0, 0, 1] , ... },
  "exit": "3,2",
  "path": ["S", "E", "W", ...],
  "budget_remaining": 37
}
```

- `"map"`: one entry per cell `"row,col"`; each value is a list of four flags in
  direction order `['N','S','E','W']`: `1` = that passage is open, `0` = wall.
  Provide the flag for **all** cells in the whole grid and it must equal exactly
  the true layout.
- `"exit"`: the `"row,col"` of the exit cell.
- `"path"`: a list of directions that starts at the start cell, never crosses
  a wall, and ends on the exit cell. It need not be shortest, but it must be
  legal and computed from your map (e.g. BFS).
- `"budget_remaining"`: your remaining `m.budget()`.

The verifier re-derives the layout per-cell from the maze module and checks
your `map`, your `exit`, wall-crossing/legality of every path step, that the
path reaches the exit and that you ended inside the budget.

### The reference fixture (debug step)

`/app/reference_maze.py` is a **known** 5x5 maze: `DIMS=(5,5)`, `START`, and a
plain `OPEN[(r,c)]` dict (cell -> set of open directions). Use it to validate
your flood-fill / full-coverage logic **offline** before trusting it on the
live unknown mazes.

`python3 /app/solve.py selfcheck` must flood this fixture and then print a
line `SELFCHECK-OK=1` and exit 0 **only when your flood covers all `DIMS[0]*DIMS[1]`
(=25) cells**. Any missing cell must yield exit ≠ 0 / no `SELFCHECK-OK=1`.

---

## Part B — chess mate-in-1 (game side)

Positions are supplied as JSON files. Implement (stdlib only, from scratch as
you like) a **mate-in-1 search**: for the side to move, find **every** legal
move that gives immediate checkmate, and write each as lowercase
source-to-destination coordinate (e.g. `a8h8` → four chars, `src`+`dst`, no
promotion/castling marker).

### Position file format

```json
{
  "id": "name",
  "side_to_move": "w",
  "pieces": [ ["w","k","e1"], ["w","q","b8"], ["b","k","h1"] ]
}
```

- `pieces`: list of `[side, type, square]`. Sides `w`/`b`; types `k`, `q`, `r`,
  `b`, `n`. Squares: file `a`..`h`, rank `1`..`8` (rank 1 bottom).
- `side_to_move`: `"w"`; still read it as a field.
- A key may be absent/mis-shaped in an edge case (below).

### The exact ruleset (the verifier recomputes from it)

- Standard 8x8 board; only `K Q R B N` exist, so there is **no pawn, no en
  passant, no castling, no promotion**.
- A move is **legal** for the side to move iff, on the post-move board, that
  side's own king is not in check. The side to move's king is always present.
- A move is **winning** iff it is legal **and** the resulting position is
  **checkmate**: the opponent's king is in check and all replies are illegal —
  the defender cannot step to a non-checked square, and cannot escape by
  capturing the checking piece if that square is defended by another enemy
  piece.
- If the opponent has no king at all, there is no mating move (report `[]`).
- Deduplicate and output the surviving moves in **ascending lexicographic
  order**, e.g. `["a6c8","g2g7"]`.

### Must-support edge cases (hidden tests probe each)

- a position that has **multiple** legal mates → include all of them, sorted;
- a position with **zero** mates-in-one → output `[]`;
- a position with **no opponent king** (no black pieces present) → `[]`;
- positions whose only "mate" would be blocked by another piece / such that the
  opponent can slip a safe square are NOT mates → do not emit them.

### Output

`python3 /app/solve.py game <position.json> <out.json>` writes `<out.json>` as a
JSON **array** (possibly empty) of winning-move strings, e.g. `["d6e7"]`.

---

## The deliverable CLI contract

```
python3 /app/solve.py                         # build /app/answer.json
python3 /app/solve.py maze <id> <out.json>    # write maze result schema
python3 /app/solve.py game <pos.json> <out.json>  # write array of winning moves
python3 /app/solve.py selfcheck               # 25/25 coverage -> SELFCHECK-OK=1 + exit 0
```

### answer.json schema

```json
{
  "mazes": { "<maze_id>": { ...maze result schema... } },
  "games": { "<game_id>": [ "e2d1", "e2d5" ] }
}
```

- Visible mazes to fully solve: `maze-verdigris` and `maze-brass`.
- Visible games: the files `/app/games/kinghand-1.json` and
  `/app/games/kinghand-2.json`; for each put its `"id"` → its sorted
  winning-move list under `games`.

`/app/solve.py` must *do* the work (navigate mazes, search mate-moves) and
reproduce `answer.json` on every clean run — never by copying a precomputed
blob.

## Constraints

- Python 3.12, **standard library only**. No additional packages.
- Deterministic: no randomness, no real time, no network.
- Keep `/app/mazeapi.py`, `/app/reference_maze.py`, and `/app/games/*` intact.
- `/app/solve.py` must be executable (`chmod +x /app/solve.py`).

## How you are judged

The verifier runs `solve.py` on the visible fixtures and on hidden maze ids
(sizes 6..9 with different cycles/layouts/exits) and hidden positions (a single
mate, several mates, a no-mate position, and a position without an opponent
king). Every maze `map`/`exit`/legal-`path`, and every winning-move list must
exactly match the independently recomputed reference; `selfcheck` must return
`SELFCHECK-OK=1`. Any single mismatch fails the whole task — be exact and
general.