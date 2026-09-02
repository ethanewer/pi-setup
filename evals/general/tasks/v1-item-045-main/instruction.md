# Item-045 (medium) — Reverse-engineering a black-box ReLU network

You are given a trained neural network as a **black box**: you may call its
`predict(x)` method, but you may not inspect its internal parameters. You must
reverse-engineer the **piecewise-linear function** the network computes: the
locations of its linear-segment boundaries ("kinks") and the affine
(`slope*x + intercept`) rule on every segment. Then you must validate that your
recovered piecewise-linear function matches the network on fresh inputs.

## Files already in the container

- `/app/model.py` — defines `ReLUMLP`, a scalar two-layer ReLU network:
  - `model.predict(x)` — evaluates the network at `x` (a Python float, or an
    iterable/array of floats). Hidden units use ReLU. It is the **only**
    allowed way to interact with the network.
  - `model.breakpoints()` — an internal helper you may use only for your own
    (NOT required for a correct solution).
  - `load_model()` — returns a `ReLUMLP` instance on the domain `x in [-4, 4]`.

The network output is a continuous piecewise-linear function of its single
input. Because every hidden unit is a ReLU of a scalar, the function's kinks
occur exactly where `w1_i*x + b1_i == 0` for some hidden unit, and the output
is affine between consecutive kinks.

## What to do (stages)

1. **Probe the network.** Sample the function over `[-4, 4]` and estimate its
   local gradient. Because the function is piecewise-linear, the numeric
   second difference of `model.predict` is ~0 inside each segment and sharply
   non-zero at the kinks. Use a sufficiently fine probe grid to discover
   *where* the kinks are; by itself, one *global* regression will not separate
   the segments.

2. **Recover affine parameters.** Between consecutive kinks fit `y = slope*x
   + intercept` robustly (e.g. least squares over a few interior sample
   points, or from one-sided slope estimates). If you like, refine each kink
   position by intersecting the two adjacent fitted lines.

3. **Build a module `.py`** at `/app/probe.py`. It must expose exactly these
   functions:
   - `segment(model, lo, hi)` -> `list[dict]`; input `model` is any object
     with a scalar `predict`; returns a **contiguous, gap-free tiling** of
     `[lo, hi]` into segments, each a `dict` with float keys `left`, `right`,
     `slope`, `intercept`. Segment 0 must have `left == lo` (within `1e-6`),
     the last segment `right == hi`, and adjacent segments must meet
     (`seg[i]["right"] == seg[i+1]["left"]`, within `1e-4`). No segment is
     empty.
   - `evaluate(segs, xs)` -> float-array: evaluates the recovered
     piecewise-linear function (from `segment`) at every value in `xs`
     (scalar or array). Must agree with `model.predict(xs)` on every segment.

4. **Validate on fresh inputs.** Write a small self-check: import
   `/app/model.py`, build `m = load_model()`, call `seg =
   segment(m, -4, 4)`, then test `evaluate(seg, xs)` against `m.predict(xs)`
   on several hundred probe values, and print the max absolute deviation.
   Also print `len(seg)` (the number of linear regions) and the kink
   locations. It should be stable to a handful of seeds.

5. **Produce a short report** `/app/report.md` (plain text) containing:
   - the number of recovered segments for the loaded model,
   - the recovered kink x-locations (rounded to 3 decimals),
   - the per-segment `(slope, intercept)` table,
   - a one-line note on how fresh-input validation went.

## Deliverables / success criteria

- `/app/probe.py` defines `segment` and `evaluate` as specified.
- `/app/models.md` exists.
- Your `segment` generalizes to a fresh (unseen) `ReLUMLP`: the verifier will
  build its own instance with a private random seed, call your
  `segment(fresh_model, -4, 4)`, and require:
  - the segments tile `[-4,4]` exactly and contiguously,
  - the number of segments equals the true number (number of distinct kinks
    strictly inside the domain, plus one; within ±1),
  - `|evaluate(seg, x) - fresh.predict(x)| < 0.05` for a dense fresh validation
    set of ~5000 points in `[-4,4]`.
- Do not modify `/app/model.py`. Do not read or change `model.w1`, `.b1`,
  `.w2`, `.b2` or `.breakpoints` from the *agent script* — the fresh model used
  for grading is opaque.