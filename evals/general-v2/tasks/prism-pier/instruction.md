# Prism Pier — Grid Cartography & Maze Finalization

You are the solo cartographer for the **Prism Pier** expedition: a crew has mapped a
procedurally generated pier-maze, and you must turn its raw survey data into reusable code
and a final, cleaned map. Everything is **Python 3.12** with the **standard library only**.
Work in `/app`. Your four deliverables are checked by an automated verifier on the real
fixture and on hidden inputs, so every function must be general (no hard-coded answers).

Leave these provided files untouched: `session_core.py`, `tile.txt`, `example_tasks.txt`,
`timing_room.json`. Do not read or rely on anything outside `/app`.

---

## 1. Grid expansion — deliverable `/app/grid.py`

Implement an importable function:

```python
def expand(tile):
    ...
```

`tile` is a `2x2` list-of-lists of integers. Return a `6x6` list-of-lists produced by this
**deterministic rule** (compute it generally for any `tile`, never special-case one input):

1. **Tile**: cover the 6x6 with 3×3 copies of `tile`, so the cell at `(r,c)` is
   `tile[r % 2][c % 2]`.
2. **Horizontal shift**: shift every row `r` circularly **left by `(r % 3)`** columns —
   the element originally at column `c` lands at column `(c - (r % 3)) % 6` (equivalently,
   the value at output column `c` is taken from input column `(c + (r % 3)) % 6`).
3. **Vertical shift**: shift every column `c` circularly **down by `(c % 3)`** rows — the
   value at output row `r` is taken from the row `(r - (c % 3)) % 6`.

Verification example — `expand([[1, 2], [3, 4]])` must return exactly:

```
[1, 4, 2, 2, 3, 1]
[4, 2, 3, 3, 1, 4]
[1, 3, 1, 2, 4, 2]
[3, 2, 4, 4, 1, 3]
[2, 4, 1, 1, 3, 2]
[3, 1, 3, 4, 2, 4]
```

The verifier will call `expand()` on other 2×2 tiles (including ones with repeated values)
and compare the full 6×6.

## 2. Arc-style grid transform — deliverable `/app/algo.py`

Implement a pure function:

```python
def map(grid):
    ...
```

`grid` is an `NxN` list-of-lists of integers; return an `NxN` list-of-lists where every cell
becomes the value of that cell **plus its mirror across the grid's vertical midline**
(the cell in the same row, opposite column). Concretely:

```python
out[r][c] = grid[r][c] + grid[r][N - 1 - c]
```

Study `example_tasks.txt`; your implementation must reproduce those examples and generalize
to any square grid for the hidden cases (including a `1x1` grid, where the result is double
the single cell).

## 3. Maximal square area — deliverable `/app/squares.py`

Implement an importable function:

```python
def maximal_area(matrix):
    ...
```

`matrix` is a 2D list-of-lists of `0`/`1`. Return the **area** (integer, `best_side ** 2`)
of the largest axis-aligned square composed entirely of `1`s. `timing_room.json` is a typical
sizing matrix you should be able to solve with your own function. Edge cases the verifier
will probe with your function:

- an empty matrix `[]` → `0`;
- a matrix with no `1` → `0`;
- a `1x1` matrix `[[1]]` → `1`;
- rectangular matrices (rows ≠ columns) → correct squared side length.

The dynamic program must be correct for all of these, including the ones in the hidden set.

---

## 4. Final map — deliverable `/app/map.txt`

The final piece is producing the pier's official map file. It is derived from your own
`expand` function plus a session that **must be finalized** before the file is written.

Steps, in order:

1. Read the 2×2 tile from `/app/tile.txt` (space/whitespace separated integers, one row per
   line).
2. `expanded = grid.expand(tile)` → a 6×6 integer grid.
3. Build the marker grid (list of strings, one per row, exactly 6 chars each):
   - value **odd** → wall `#`;
   - value **even** → open floor `.`;
   - then place the **start** `S` on the top-most row, in its left-most open `.` cell;
   - place the **exit** `E` on the bottom-most row, in its right-most open `.` cell.
4. Open the session and finalize it (this is essential — see next paragraph):

```python
from session_core import MazeSession
sess = MazeSession(marker_grid_rows)          # a list of 6 char strings
sess.flag_visited([(r, c) for r, row in enumerate(marker_grid_rows)
                   for c in range(len(row)) if row[c] == '.'])
sess.finalize()                                # turns the 'X' visit marks into '.'
sess.write_map('/app/map.txt')                 # must happen ONLY after finalize()
```

Because you mark every open floor cell as visited (they become `X`), a map saved **before**
`finalize()` would still contain `X` residues and would be rejected. Calling
`finalize()` then `write_map()` produces the correct `/app/map.txt`. Every file is matched
after trimming trailing whitespace on each line; blank lines are ignored. `/app/map.txt`
must therefore contain exactly 6 non-empty lines (one per row).

## Constraints

- Write everything under `/app`. Only the four deliverables above are graded, but their
  correctness is what passes the hidden-input verifier.
- `expand`, `map`, and `maximal_area` must be pure and callable with new inputs; the hidden
  verifier imports and calls them directly as `grid.expand`, `algo.map`,
  `squares.maximal_area`.
- Standard library only; do not install packages.

When you are done, double-check that `/app/map.txt` exists, has 6 lines, and matches the
rule above exactly.