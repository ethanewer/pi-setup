# Vine-Delta Arcade-Solver

You are provisioning a small, standalone solver for the Vine-Delta board — five
discrete stations run by one Python module. Everything is pure computation with
the Python 3.12 **standard library only**. Do not use numpy, external packages,
system services, or network calls.

You must produce **two deliverables** in `/app`:

1. `/app/solve.py` — an importable module (i.e. `import solve` works when the
   current directory is `/app`) exposing the functions below.
2. `/app/moves.txt` — a generated text tape produced **by running** your own
   solver (see "Lane station" and the canonical session below), not by hand.

The verifier imports `/app/solve.py`, runs every function on its own hidden
inputs (including edge and malformed cases), re-generates `/app/moves.txt` with
your code to confirm it is reproducible, and checks behavior on new inputs. You
only ever write two files: `/app/solve.py` and `/app/moves.txt`. Do not add
other files. Keep the module deterministic (no randomness, no clocks, no I/O
beyond the socket passed to `play`).

---

## Required API of `/app/solve.py`

The module must be importable and define, at top level, the functions below.
Function names, parameter lists, return types, and error behavior are part of
the contract and are verified exactly.

### 1. `max_quiet_gap(cycles)` — periodic-scheduling maximum gap

Three event schedules fire on integer day indices. Schedule $i$ fires on day
$d$ (for $d = 0,1,2,\dots$) whenever $d$ is divisible by `cycles[i]`. A day that
no schedule fires on is a *silent* day. The three schedules together repeat
every $\mathrm{lcm}(a,b,c)$ days (day 0 and day $L$ both fire). Define the gap
between two consecutive firing days $d_1 < d_2$ as the number of silent days in
between, $d_2 - d_1 - 1$.

- **Input:** `cycles` — an iterable of positive integers; the first three are
  used as the cycle lengths (any extras are ignored).
- **Return:** the maximum such gap (an `int`, `>= 0`), i.e. the longest run of
  consecutive silent days between two firing days. If every day fires (any
  cycle length is 1) the answer is `0`.
- **Error behavior:** if any of the first three cycle lengths is not a positive
  integer, raise `ValueError`.

Examples:
- `max_quiet_gap([2, 3, 5])` → `1`
- `max_quiet_gap([1, 3, 5])` → `0`

### 2. `weighted_return(weights, values)` — weighted-return dot product

Compute the dot product $\sum_i w_i \cdot v_i$ as a `float`.

- **Parameters:** two iterables of numbers of equal length.
- **Returns:** a Python `float` equal to the dot product (must match a
  reference value within `1e-9`).
- **Error:** if the two lists differ in length, raise `ValueError`.
- Empty equal-length lists → `0.0`.

Example: `weighted_return([0.5, -1.0, 2.0], [2.0, 3.0, 1.0])` → `0.0`.

### 3. `solve_sudoku(board)` — standard 9x9 Sudoku

Fill every empty cell so each row, column, and 3×3 box contains the digits 1–9
exactly once.

- **Parameter:** `board` — a 9×9 nested list of `int`, `0` marks an empty cell.
- **Behavior:** modify the grid and then **return** the fully solved grid (as a
  nested list of 9 rows × 9 columns of `int`). The completed grid must be a
  valid, uniquely correct completion.
- **Error:** if the input is not exactly 9 rows of 9 cells (e.g. a non-9×9
  shape), raise `ValueError`. If the puzzle has no valid completion, raise
  `ValueError`.

Solving must work on any well-posed input puzzle, not just one example; the
verifier feeds several different puzzles.

### 4. `play(sock)` — the lane strategy entrypoint (exact signature)

`play(sock)` is the strategy entrypoint. It must take **exactly one parameter**
(a socket-like object); a wrong parameter count fails the check.

A "lane" is a 1-D row of cells drawn from `.` (walkable) and `#` (blocked/void).
Each turn the engine sends the strategy **one descriptor line** through the
socket, of the form

```
N CELLS POS
```

where `N` is the lane length, `CELLS` is a string of exactly `N` characters
(`.` or `#`), and `POS` is the current position index (`0 <= POS < N`). Each
descriptor occupies one line and ends with a newline.

A **legal move** on a turn is an index `i` with:
- `0 <= i < N`
- `i != POS`
- `CELLS[i] == '.'`  (never moves onto a blocked cell)

`play` must, **for every turn** (every descriptor line it reads until EOF where
`recv()` returns the empty string), send **exactly one reply** via `sendall()`
(a str or bytes ending in `\n`). It must never send two replies for one turn,
never pause silently, and never crash. The reply is chosen as:

- if at least one legal move exists, send one of them, **preferring the lowest
  valid index**;
- if no legal move exists this turn (e.g. all cells are `#`, or `N == 1`), send
  the literal hold marker `-1`;
- if the descriptor is **malformed** (non-integer `N`/`POS`, or `CELLS` length
  != `N`), send the literal marker `ERR`.

So the strategy always emits exactly one well-formed token per turn and never
aborts on malformed or dead-end input. Implementation freedom:

```
class FakeSocket:        # engines you test with behave like this
    def __init__(self, lines): self.lines = list(lines); self.out = []
    def recv(self): return self.lines.pop(0) if self.lines else ""
    def sendall(self, data):
        s = data.decode() if isinstance(data, bytes) else str(data)
        self.out.append(s.strip())   # .strip() removes the trailing newline
```

Example: descriptor `"3 ... 0"` → legal moves `{1, 2}` → reply `1`.
Descriptor `"2 ## 0"` → no legal move → reply `-1`.
Descriptor `"3 .. 0"` (length mismatch) → reply `ERR`.

### 5. `gen_moves()` and the `--gen-moves` mode (used to build `moves.txt`)

The module must also provide a module-level function `gen_moves()`, returning a
single `str` (a tape), and a `cli` path: when run as
`python3 /app/solve.py --gen-moves`, the program writes that string to
`/app/moves.txt`. Both must draw on the **same canonical session** below, and
both must use the **same turn logic** as `play`.

The canonical session is a fixed sequence of descriptors:

```
3 ... 0
3 ... 1
3 .#. 0
4 .#.. 2
5 ..#.. 1
2 ## 0
6 .#.#.. 3
1 . 0
```

`/app/moves.txt` must be exactly, one reply per line (the same replies the
strategy would give for those descriptors, lowest-legal-index rule), with a
final newline. `/app/moves.txt` must be **reproducible**: the verifier derives
the same text independently and re-runs `gen_moves()` and requires them equal.

---

## Verifier behaviour (what must hold)

The verifier does **not** use a visible golden answer file. It imports your
`/app/solve.py` and:

1. checks all four required callables exist and that `play` has exactly one
   parameter;
2. runs `max_quiet_gap` on several hidden `cycles` vectors (including edge
   cases) and compares exact integer answers, and requires `ValueError` on a
   non-positive cycle;
3. runs `weighted_return` on several hidden vectors, compares within `1e-9`,
   and requires `ValueError` for mismatched lengths;
4. runs `solve_sudoku` on several hidden 9×9 puzzles (exact completed grid must
   match, rows/columns/boxes all distinct), and requires `ValueError` on a
   non-9×9 grid;
5. drives `play` through a real socket-like object over several hidden turn
   scenarios: normal lanes, fully-blocked lanes (`-1`), and malformed
   descriptors (`ERR`), asserting exactly one reply per turn and that every
   move is legal/in-bounds on non-blocked cells;
6. checks `/app/moves.txt` byte-for-byte against both `gen_moves()` and an
   independent replay of the canonical session.

The whole thing runs server-side under the standard library; your code must be
fast and deterministic (hidden Sudoku puzzles are standard and complete in
well under a second each).

## Getting started

1. Author `/app/solve.py`.
2. Run `cd /app && python3 solve.py --gen-moves` to write `/app/moves.txt`.
3. Sanity check the visible examples above.

Deliverables: `/app/solve.py` and `/app/moves.txt`.