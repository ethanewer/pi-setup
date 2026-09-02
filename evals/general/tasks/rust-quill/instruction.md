# Rust Quill — freight-plan transport distance

The `Rust Quill` freight desk stores optimal-transport plans as JSON matrices.
You must build a small Python module + CLI that computes the **true metric
transport distance** between a freight plan and a depot cost matrix, and run it
once on the provided fixtures.

You will produce **two deliverables**:

1. `/app/emd_distance.py` — an importable Python module that also works as a
   command-line program (interface below).
2. `/app/distance.json` — the result the module's CLI produces for the
   provided visible fixtures `/app/plan.json` and `/app/cost.json`.

## The metric

A transport plan `P` (a 2-D array of non-negative masses) and a per-unit cost
matrix `C` (same shape) define the **squared** transport cost as the scalar dot
product

    s = sum_{i,j} P[i][j] * C[i][j]

The **actual metric distance** is the square root of that scalar after
**root-clamping to non-negative** (a negative dot product is clamped up to 0):

    d = sqrt( max(0, s) )

Returning the **unrooted squared cost** (skipping the square root) is the
classic bug: the result is no longer a length and breaks metric comparisons
when costs are scaled. Your function must return the rooted distance.

## Module interface

`/app/emd_distance.py` must be importable from `/app` and expose exactly:

    from emd_distance import sqrt_wasserstein
    d = sqrt_wasserstein(plan, cost)   # -> float, the rooted distance

- `plan` and `cost` are 2-D lists of lists of real numbers (same shape).
- It returns a Python `float`: `sqrt(max(0, dot))`.
- If `plan` and `cost` shapes differ (different number of rows, or any row
  length mismatch), it must raise `ValueError`.

## CLI interface

    python3 /app/emd_distance.py --plan PLAN.json --cost COST.json --out OUT.json

- `--plan` / `--cost` — paths to JSON files holding same-shape 2-D arrays of
  numbers. On a shape mismatch the program must exit with a nonzero status.
- `--out OUT.json` — write `{"distance": d}` to that path (d as a JSON number).
- The program must also print `d` to stdout.

## Visible run

The fixtures `/app/plan.json` and `/app/cost.json` are provided. Run your CLI
on them and write the result **exactly at** `/app/distance.json`:

    python3 /app/emd_distance.py --plan /app/plan.json --cost /app/cost.json --out /app/distance.json

The verifier re-runs your program on this visible fixture, re-checks the
committed `/app/distance.json`, calls the module function directly, and runs
the CLI on **hidden** fixtures whose expected distances it recomputes
independently.

## Edge cases the hidden fixtures will probe

- An **all-zero plan** (any shape) → the distance is exactly `0.0`.
- A plan/cost pair whose **dot product is negative** → the distance must be
  `0.0`, never `nan` or a complex number (root-clamp before rooting).
- **Rectangular** (non-square) matrices.
- **Larger matrices** with fractional masses and costs, where the expected
  value is recomputed by the verifier from the raw matrices.
- Integer-valued matrices (the result is still a float).

## Constraints

- Standard library only; no network access at verify time; nothing under
  `/tests` exists in your environment.
- Do not delete or rename `/app/plan.json` or `/app/cost.json`.
- The verifier runs your program **unchanged** on hidden fixtures, so do not
  hard-code to the provided file contents or filenames.
