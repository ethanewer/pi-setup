# Rooted transport distance for freight plans

The freight-analytics desk needs a single standalone metric module: given an
optimal **transport plan** `P` (a probability matrix over origin/destination
cells) and a **per-unit cost matrix** `C` of the same shape, the squared
transport cost is the scalar dot product

    s = sum_{i,j} P[i][j] * C[i][j]

and the **actual metric distance** is the square root of that scalar after
**root-clamping to non-negative** (a negative dot product is rounded up to 0):

    d = sqrt( max(0, s) )

Returning the **unrooted squared cost** (skipping the square root) is the
classic bug: the result stops being a length and breaks every metric
comparison, e.g. when costs are rescaled. Your program must return the rooted
distance.

## Environment

- Working directory: `/app`. It already contains the input file
  `/app/shipment.json`. Python 3.12 with numpy is available.
- **Do not modify `/app/shipment.json`.**

## Deliverables (both required)

1. `/app/emd.py` — a Python module that is importable as `import emd` from
   `/app` and also works as a command-line program.

   **Module interface:**

   ```python
   from emd import distance
   d = distance(plan, cost)   # -> float, the rooted distance
   ```

   - `plan` and `cost` are JSON-compatible 2-D arrays (lists of lists) of
     numbers, same shape.
   - Return a Python `float`: `sqrt(max(0.0, sum_ij plan[i][j] * cost[i][j]))`.
   - If the two arrays do not have exactly the same shape (or either is not a
     2-D non-empty rectangular array of numbers), raise `ValueError`.
   - An all-zero plan returns `0.0`. A plan whose dot product with the cost is
     negative returns `0.0` — never `nan` and never a negative number.

   **CLI interface:**

   ```
   python3 /app/emd.py <input_json> <output_json>
   ```

   - `<input_json>` holds a single JSON object `{"plan": [[...]], "cost": [[...]]}`.
   - On success: write `{"distance": d}` to `<output_json>` and exit with
     status `0`.
   - If the shapes mismatch (or the input is not a valid 2-D pair), print a
     diagnostic to stderr, write nothing to the output path, and exit with
     status `2`. Do not crash with a traceback.

2. `/app/distance.json` — the output your program produces **when run on the
   provided `/app/shipment.json`**:
   ```
   python3 /app/emd.py /app/shipment.json /app/distance.json
   ```
   with exactly the schema `{"distance": <float>}`.

## Edge cases the hidden checks will probe

- Rectangular (non-square) matrices of either orientation.
- Larger matrices (e.g. 5x4) whose expected value the verifier recomputes
  independently.
- An all-zero plan (must return `0.0`).
- A plan/cost pair whose dot product is negative (must return `0.0`, never
  `nan`).
- Shape mismatch — including same number of cells but transposed shape —
  must raise `ValueError` from `distance` and exit status `2` via the CLI.
- Integer entries mixed with float entries (e.g. `4` vs `4.0` cells).
- A `1x1` matrix and a single-row (`1xN`) matrix.

## Constraints

- The verifier imports `/app/emd.py` and runs it **unchanged** as a CLI on
  hidden inputs that follow the same format, so do not hard-code to the
  provided file contents or filenames.
- No network access at verify time; standard library and numpy only.
- Do not modify `/app/shipment.json`.