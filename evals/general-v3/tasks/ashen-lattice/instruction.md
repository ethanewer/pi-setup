# ashen-lattice — Lantern-Crawl drone turn engine

You are implementing the per-turn decision core of the **Lantern-Crawl**
delivery-drone game: a 2-D grid of signal beacons, one drone, and a set of
allowed moves per turn. Everything must be pure JavaScript with an exact
module interface — the grader loads your module and drives it directly.

Environment: Node.js (`node`) is installed. Working directory: `/app`.
The file `/app/scenario.json` already contains a visible list of turn states.

## Deliverables (all three required)

1. `/app/drone.js` — a **pure JavaScript module (no imports, no classes)**.
   The module body must not `require()` or `import` anything. It must define
   a plain function (not a class, not a factory) named exactly `choose` that
   takes **one argument** (the state object) and export it exactly as:
   ```js
   module.exports = { choose: choose };
   ```
   No networking, no randomness, no filesystem access, no `Date`.

2. `/app/simulate.js` — a batch driver with this CLI:
   ```
   node /app/simulate.js <states.json> <out.json>
   ```
   It reads a JSON file containing a **list of turn states**, applies
   `choose` to each in order (it must load the decision function from
   `/app/drone.js`), and writes a JSON list of the chosen action strings
   (same length, same order) to `<out.json>`.

3. `/app/walkthrough.json` — the output your driver produces for the visible
   fixture:
   ```
   node /app/simulate.js /app/scenario.json /app/walkthrough.json
   ```

## State object

```json
{
  "grid":    [[3, 7, 1], [8, 0, 4], [2, 9, 6]],
  "row":     1,
  "col":     1,
  "visited": [[0, 1], [2, 2]]
}
```

- `grid` — a 2-D array of numeric signal values. Rows may be **jagged**
  (different lengths); bounds are checked per row.
- `row`, `col` — the drone's current integer coordinates (`0`-indexed).
- `visited` — optional list of already-claimed cells as `[r, c]` integer
  pairs. A missing `visited` key is treated as empty (nothing claimed).
  Malformed entries (non-arrays, short arrays, non-integer coordinates,
  booleans, strings) are **ignored**, not errors.

## `choose(state)` behaviour

Return exactly one action string:

- `"north"` — neighbour `(row-1, col)`
- `"east"`  — neighbour `(row, col+1)`
- `"south"` — neighbour `(row+1, col)`
- `"west"`  — neighbour `(row, col-1)`
- `"hold"`  — no legal move (see below)

A neighbour is **allowed** iff all of these hold:

1. it lies inside the grid (`0 <= nr < grid.length`, and
   `0 <= nc < grid[nr].length` for its own row);
2. its grid value is a **finite number** (a string, boolean, null, or
   missing cell disqualifies that neighbour);
3. it is **not** marked in `visited`.

**Choosing among allowed neighbours:** pick the one with the **largest**
grid value. On a tie, prefer the first of the fixed priority order
**north > east > south > west**. If no neighbour is allowed, or the state is
malformed, return `"hold"`.

Malformed state — any of these returns `"hold"`:

- `state` is not an object, or `grid` is missing / not an array;
- `row`/`col` are missing, non-numbers, non-integers (e.g. `1.5`), or not
  finite;
- `row`/`col` out of bounds, or the drone's own row is not an array or too
  short for `col`.

Worked examples:

- `{"grid": [[3,7,1],[8,0,4],[2,9,6]], "row":1, "col":1}` → the four
  neighbour candidates are north `8`, east `4`, south `9`, west `0`; the
  largest allowed value is `9` → **`"south"`**.
- Same state with `"visited": [[2, 1]]` → south blocked; largest remaining
  is `8` (north) → **`"north"`**.

## Edge cases the grader probes (hidden states follow the same contract)

- Every value tie → priority order decides (`north`, then `east`, then
  `south`, then `west`).
- The best-valued neighbour is visited → next-best allowed neighbour wins.
- All neighbours visited or out of bounds → `"hold"`.
- Jagged grid: a neighbour that exists in another row's length but not in
  the neighbour's own row is out of bounds.
- Non-numeric neighbour values are skipped (they are disallowed, not
  treated as 0).
- Negative values are legal and participate normally.
- Single-cell grid (no neighbours) → `"hold"`.
- Boolean/float/`NaN`-ish coordinates and missing `grid` → `"hold"`.

## Constraints

- The grader loads `/app/drone.js` with `node` and calls `choose` directly
  on hidden states, and runs `/app/simulate.js` on hidden state batches. It
  also statically checks that `/app/drone.js` contains no `require(` and no
  `import` anywhere — the batch driver must keep its own `require` calls in
  `/app/simulate.js` only.
- Do not modify `/app/scenario.json`.
- No third-party packages; Node's standard library only (in
  `/app/simulate.js`).
