# 1. Tune the resonance simulator

You are handed a deterministic simulation written in Python. Your job is to produce a
**general-purpose optimizer program** that finds the best operating point of the simulator
and repairs/documents the numerically unstable step. The grader evaluates your program on
several *hidden* parameter boxes, so it must work for ANY valid box, not just the one in
`/app/bounds.json`.

## Background

`/app/sim.py` defines the public function:

```python
def score(a: int, b: int) -> float:
    """Figure-of-merit, higher is better, in [..., 100.0]."""
```

`sim.score(a, b)` grades how close the reduced ratio `a/(b+1)` is to the resonance
constant `3.75`:

```text
score(a, b) = 100 - 100 * |a/(b+1) - 3.75|
```

The module docstring documents an **unstable step**: an earlier version of the model derived
that figure with a 128-term alternating power series that suffers catastrophic cancellation
near the resonance. `sim.score` is already the closed-form, stable evaluation — use it as-is
and document that choice. Do NOT re-derive the residual with a fragile power series; do NOT
change the `score(a: int, b: int) -> float` signature.

A "best" point is one that **maximizes `score`** within a box. Ties are broken by the
smallest `a`, then the smallest `b`.

## Deliverables (both required, under `/app`)

1. **`/app/solve.py`** — a command-line optimizer with this exact contract:

   ```text
   python3 /app/solve.py <bounds_in.json> <tuning_out.json>
   ```

   It must:
   * Read `<bounds_in.json>` = `{"a": [lo_a, hi_a], "b": [lo_b, hi_b]}` (both inclusive),
     both integers with `lo <= hi`.
   * Iterate every integer point of the box (deterministic, in any order).
   * Find the point maximizing `sim.score(a, b)`; break ties by smallest `a`, then smallest
     `b`.
   * Count `evaluations` = number of integer points in the box
     `(hi_a - lo_a + 1) * (hi_b - lo_b + 1)`.
   * Write JSON `{"a": <int>, "b": <int>, "evaluations": <int>, "score": <float>}` to
     `<tuning_out.json>`.
   * On a malformed bounds file (missing `a`/`b`, non-integers, or `lo > hi`), print a short
     message to **stderr** and exit non-zero **without writing** the output file.

2. **`/app/tuning.json`** — run your program once to produce the tuned result for the
   shipped box in `/app/bounds.json` and commit that output. (This is the deliverable for the
   visible case; hidden cases are run via the CLI above.)

## Fixed inputs (DO NOT modify)

`/app/sim.py` and `/app/bounds.json` are inputs to your task and **must not be modified**.
Create only the two deliverables `/app/solve.py` and `/app/tuning.json`. You may add your own
auxiliary helper scripts under `/app`.

## Expected result for the shipped box

`/app/bounds.json` is `{"a":[0,20], "b":[0,20]}`. Its best point is `a=15, b=3` with
`score=100.0` and `evaluations=441`. Use this to sanity-check `/app/tuning.json`.

## Edge cases hidden cases probe

The grader runs `python3 /app/solve.py <hidden_bounds> <out>` and checks the output
against an independent exhaustive search on the SAME box:

- **Tie-breaking** — always pick smallest `a`, then smallest `b`, among maximizing points.
- **Single-point boxes** (e.g. `a` and `b` each one value) — grid of 1 cell, valid.
- **Score precision** — the exact formula above; compare with the float arithmetic you used so
  `score` matches to at least `1e-6` relative tolerance.
- **Malformed input** — a box missing a key or with `lo > hi`; your program must exit non-zero
  and must NOT write the output file.

No network access is available. Everything must be deterministic and self-contained.