# Rooted haulage distance from CSV transport ledgers

The haulage desk stores an earth-moving **transport plan** `P` (fraction of
each tonne routed over an origin/destination cell) and a **per-unit cost
ledger** `C` (same shape) as two plain CSV tables. The squared transport cost
is the scalar dot product

    s = sum_{i,j} P[i][j] * C[i][j]

and the **actual metric distance** is the square root of that scalar after
**root-clamping to non-negative** (a negative dot product is rounded up to 0):

    d = sqrt( max(0, s) )

Returning the **unrooted squared cost** (skipping the square root) is the
classic bug: the result stops being a length and breaks every metric
comparison, e.g. when costs are rescaled. Your program must return the rooted
distance.

## Environment

- Working directory: `/app`. It already contains the input files
  `/app/plan.csv` and `/app/cost.csv`. Python 3.12 is available as `python3`.
- **Do not modify `/app/plan.csv` or `/app/cost.csv`.**

## Deliverables (both required)

1. `/app/movecost.py` — a Python module that is importable as
   `import movecost` from `/app` and also works as a command-line program.

   **Module interface:**

   ```python
   from movecost import route_distance
   d = route_distance(plan, cost)   # -> float, the rooted distance
   ```

   - `plan` and `cost` are JSON-compatible 2-D arrays (lists of lists) of
     real numbers, same shape.
   - Return a Python `float`:
     `sqrt(max(0.0, sum_ij plan[i][j] * cost[i][j]))`.
   - If the two arrays do not have exactly the same shape (or either is not a
     non-empty 2-D rectangular array of real numbers), raise `ValueError`.
   - An all-zero plan returns `0.0`. A plan whose dot product with the cost
     is negative returns `0.0` — never `nan` and never a negative number.

   **CLI interface:**

   ```
   python3 /app/movecost.py <plan_csv> <cost_csv> <output_json>
   ```

   - `<plan_csv>` / `<cost_csv>` are plain-text tables of numbers, one matrix
     row per line; cells separated by commas (optionally surrounded by
     spaces) or by whitespace. Blank lines may appear anywhere and are
     ignored. No header rows.
   - On success: write `{"distance": d}` to `<output_json>` (valid JSON,
     exactly that one key) and exit with status `0`.
   - If the tables cannot be parsed as matrices of real numbers, or their
     shapes differ, print a one-line diagnostic to stderr, write nothing to
     the output path, and exit with status `1`. Do not crash with a
     traceback.

2. `/app/answer.json` — the output your program produces **when run on the
   provided `/app/plan.csv` and `/app/cost.csv`**:
   ```
   python3 /app/movecost.py /app/plan.csv /app/cost.csv /app/answer.json
   ```

## Edge cases the hidden checks will probe

- Rectangular (non-square) matrices of either orientation (tall and wide).
- Larger matrices (e.g. 5x4) whose expected value the verifier recomputes
  independently.
- An all-zero plan (must return `0.0`).
- A plan/ledger pair whose dot product is negative (mixed positive and
  negative ledger entries) — must return `0.0`, never `nan`.
- Shape mismatch — including the same number of cells but transposed shape —
  must raise `ValueError` from `route_distance` and exit status `1` via the
  CLI.
- Integer entries mixed with float entries (`4` and `4.0` cells).
- Very small magnitudes (e.g. `1e-6`-scale entries), where the square root
  must preserve relative precision.
- A `1x1` matrix and a single-row (`1xN`) matrix.

## Constraints

- The verifier imports `/app/movecost.py` and runs it **unchanged** as a CLI
  on hidden inputs that follow the same format, so do not hard-code to the
  provided file contents or filenames.
- No network access at verify time; standard library only.
- Do not modify `/app/plan.csv` or `/app/cost.csv`.
