# Item-045 (hard) — Reverse-engineering a deep black-box ReLU network

You must reconstruct the piecewise-linear scalar function computed by a
trained neural network that you may **only query** through its public
`predict()`, using an efficient probing strategy, and validate your recovered
parameters against inputs you have never scored during development. The harder
variant scales the network (more hidden units + denser kinks, some possibly
nearly-coincident and / or producing near-zero slope changes) and requires you
to *infer* the piecewise structure from a limited number of informative probes
(not just read every value).

## Files already in the container

- `/app/model.py` — same `ReLUMLP` class as the companion task, but the model
  now has `num_hidden=12`. You must treat every numeric member (
  `w1`, `b1`, `w2`, `b2`, `breakpoints`) as **off limits**. The only public
  surface is:
  - `model.predict(x)` — scalar or iterable input `x`.
  - `load_model()` — returns the subject instance; evaluate on `x in [-6,6]`.

Like before, `predict` is continuous and piecewise-linear: each hidden unit is
`max(0, w1_i x+b1_i)` and contributes `w2_i * h_i`, so the sum is affine
between the kinks `-b1_i/w1_i`.

## What to do (stages)

1. **Design informative probes.** The function is piecewise-linear but you do
   NOT know its number of kinks. Use coarse-then-fine probing: first estimate
   the number of kinks on a coarse grid; then re-sample adaptively so no
   segment is missed (including two kinks closer than the initial grid
   resolution, or a segment whose slope is nearly equal to a neighbor's).
   Because near-coincident kinks and near-flat segments are present, do not
   trust a single second-difference threshold.

2. **Recover affine parameters per region.** Fit `slope, intercept` on interior
   points that are safely away from the two neighboring kinks. Refine each
   breakpoint using a robust estimator (e.g. intersect the adjacent two fitted
   lines, then verify with a two-sided one-point check). Do not fabricate extra
   segments: a region with zero width must be dropped.

3. **Implement `/app/probe.py`** exactly as the companion task:
   - `segment(model, lo, hi)` -> list of dicts `{"left","right","slope",
     "intercept"}` tiling `[lo,hi]` contiguously (boundary conditions in the
     companion task's instructions),
   - `evaluate(segs, xs)` -> array of the piecewise-linear function.

4. **Validate adversarially.** Write a self-check that, for
   `m=load_model()`, does:
   - uniform probe: 4000 grid points in `[-6,6]`, and
   - adversarial "near-kink" probes: 5 points within `±0.01` of **every**
     recovered kink location; the maximum absolute deviation over all of them
     must be `< 0.05`.
   Print the counts, the max error, and the kinks.

5. **Write `/app/inferred.json`** with these JSON keys:
   - `"segments"`: int (number of recovered piecewise regions),
   - `"kinks"`: list of floats,
   - `"max_uniform_error"`: float,
   - `"max_near_kink_error"`: float,
   - `"validated"`: bool (true iff both maxes `< 0.05`).
   Also keep `/app/models.md` (short narrative).

## Deliverables / success criteria

- `/app/probe.py` exposes `segment` / `evaluate` as specified.
- `/app/inferred.json` and `/app/models.md` exist and are non-empty.
- `segment;/fit resolve` the **fresh hidden model**, with fixed potential seeds
  `range`. The verifier builds a `ReLUMLP(num_hidden=12)` with its own random
  seed, calls `segment(fresh, -6, 6)`, and requires:
  1. a contiguous tiling of `[lo,hi]`,
  2. segment count equals the true number of distinct interior kinks + 1
     (within ±1),
  3. `evaluate` differs from `model.predict` by `< 0.05` on both a uniform
     set of 8000 points and on points located right at each recovered kink
     (this is the adversarial part — sloppy breakpoint localization fails
     here).
- Do not modify `/app/model.py`.