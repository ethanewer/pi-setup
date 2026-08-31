# tundra-quill — Coldstore aisle pilot

The **Coldstore** warehouse runs autonomous picking robots along frozen
aisles laid out as a grid. You must author a single pure-JavaScript decision
module, `/app/pilot.js`, that chooses the robot's next move for any given
cell state. It is graded by loading the file and calling the function on
hidden states, so it must implement the contract below **exactly** and work
on any conforming input.

## Environment

- Working directory: `/app`. Node.js (`node`) is installed.
- There are no provided inputs; the module itself is the whole deliverable.

## Deliverable (required)

`/app/pilot.js` — a plain JavaScript file with **no imports of any kind**
(it must not call `require()` nor use `import` syntax, and must not declare
a class) exposing exactly this interface:

```js
function step(cell) {
    // ... pure decision logic, no networking, no randomness ...
}

module.exports = { step: step };
```

The exported `step` must be a **plain function** (not a class, not a class
method) and the module must be loadable with `require('/app/pilot.js')`.

## Input `cell` — the robot's state

```json
{
  "grid":    [ [ { "cost": 2 }, { "cost": 0, "blocked": true } ], [ { "cost": 5 } ] ],
  "row":     0,
  "col":     0,
  "battery": 4
}
```

- `grid` — a 2D array of rows; each row is an array of **cell objects**.
  A cell object may carry:
  - `blocked` — if present and exactly `true`, the cell is impassable ice;
  - `cost` — a number (>= 0); a missing or non-number `cost` counts as `0`.
- `row`, `col` — integer indices of the robot's current cell (row first).
- `battery` — optional number; the robot's remaining charge.

## Behaviour — the returned action string

`step(cell)` returns exactly one of the strings `"north"`, `"south"`,
`"east"`, `"west"`, `"hold"`, where north = one row up (`row - 1`), south =
one row down (`row + 1`), east = one column right (`col + 1`), west = one
column left (`col - 1`).

**Malformed state → `"hold"`** (checked in order):

1. `cell` is not an object (null / array / non-object);
2. `grid` is missing or not an array;
3. `row` or `col` is not an integer number;
4. `row` / `col` are out of the grid bounds, the robot's row is not an
   array, or the current cell is not an object.

**Out of energy → `"hold"`**: if `battery` is present and is a number `<= 0`,
the robot must return `"hold"` even when moves exist. A missing or non-number
`battery` imposes no restriction.

**Choosing a move:** consider the four neighbours. A neighbour is *eligible*
only if it is within bounds, exists, is an object, and is not
`blocked: true` (a missing `blocked` field counts as open). Among eligible
neighbours pick the one with the **smallest** `cost` (missing / non-number
cost = 0). On a **tie**, prefer the first in this fixed order:
`north`, then `south`, then `east`, then `west`.
If no neighbour is eligible → `"hold"`.

Example: `grid = [[{"cost":0},{"cost":0},{"cost":0}]], row = 0, col = 1` →
both east and west are eligible with cost 0, north/south out of bounds →
`"east"` (east beats west on a tie).

## Edge cases the grader probes (hidden)

- Ties in every pair of directions (including north/south and east/west).
- A cheaper neighbour that is `blocked: true` must be skipped in favour of
  a costlier open one.
- Missing `cost` fields (treated as 0) and missing `blocked` fields (treated
  as open).
- A neighbour slot that is `null` or not an object is not eligible.
- `battery: 0` (or negative) forces `"hold"`; a missing `battery` does not.
- Empty grid `[]`, out-of-bounds `row`/`col` (including negatives),
  non-array `grid`, non-integer or non-number `row`/`col` — all `"hold"`.

## Constraints

- No imports, no `require()`, no classes, no networking, no randomness, no
  filesystem access. The verifier rejects sources containing `require(`
  calls, top-level `import` statements, or `class` declarations.
- Pure function of the input: the same `cell` always yields the same string.
- Do not create or write anything under `/tests` (mounted read-only at
  verify time); the module is graded purely by requiring `/app/pilot.js`.
