# Item-001 (hard) — Generic adaptive rejection sampling for two log-concave targets

You are a statistical programmer on a Monte-Carlo team. The package must draw
i.i.d. samples from **any** unnormalized log-concave density via **adaptive
rejection sampling (Gilks & Wild 1992)**. This hardened assignment runs the
sampler against **two** different log-concave targets and requires strict,
statistically-validated quality for both, plus a matching pytest suite.

## Files already in the container

- `/app/target.R` — declares two unnormalized log-concave targets:
  - **T1** = standard Normal restricted to `[-4, 4]` (`log_fun1`, `log_deriv1`,
    `LO1 = -4`, `HI1 = 4`).
  - **T2** = Laplace(location 0, scale 0.8) restricted to `[-6, 6]`
    (`log_fun2`, `log_deriv2`, `LO2 = -6`, `HI2 = 6`). Note T2 has a
    non-differentiable cusp at 0 — a real generic sampler must still handle it.
  All `log_*` functions are vectorizable; they accept a numeric vector and
  return the same-length vector.
- `/app/ars.R` — declares
  `ars_sample(log_fun, log_deriv, left, right, n, seed)`. It must return a
  length-`n` numeric vector of i.i.d. draws from the given target. The current
  implementation is defective (both targets fail statistical checks).
- `/app/evaluate.R` — the evaluator. It calls your `ars_sample` for T1
  (seed 51) and T2 (seed 52), writes `/app/samples_t1.tsv` and
  `/app/samples_t2.tsv` (one number per line), and checks, per target:

  - **T1**: `|mean| < 0.2`; `|sd − 1| < 0.15`; histogram chi-square vs N(0,1)
    (bins of width 0.2) `< 100`.
  - **T2**: `|mean| < 0.25`; `0.95 < sd < 1.35` (true sd ≈ 1.13); histogram
    chi-square vs the Laplace CDF `F(x) = 0.5*exp(x/0.8)` for `x<0`,
    `1 − 0.5*exp(−x/0.8)` otherwise (bins of width 0.3 over `[-6,6]`) `< 120`.

  It prints a per-target report and finishes with `PASS` / `FAIL`, writing the
  verdict to `/app/status.txt`.

## What to do (work in stages)

1. **Read the contract**. Understand both targets, the exact return contract
   of `ars_sample`, and every check `evaluate.R` performs.
2. **Run the evaluator** to observe the current failures:

   ```bash
   cd /app && Rscript evaluate.R
   ```

3. **Fix `/app/ars.R`** so that `ars_sample` is a *generic* adaptive rejection
   sampler:
   - Signature and return type must be unchanged (`length-`n` numeric`).
   - It must build a piecewise-linear tangent (upper) hull around
     `log_fun`, draw from the corresponding piecewise-exponential proposal,
     accept/reject against the true density, and add rejected points to the
     knot set (adaptive refinement). It may assume `log_fun` is log-concave on
     `[left, right]`.
   - It must work for *both* T1 and T2 — do not special-case either target.
   - `seed` must make the output reproducible.
4. **Iterate** until `Rscript evaluate.R` prints `PASS` (both targets).
5. **Write statistical tests**: create `/app/tests/test_sampler.py` (pure
   Python standard library; `math` is fine, no numpy) covering **both**
   targets:
   - read `/app/samples_t1.tsv` and assert: 20000 values; all in `[-4,4]`;
     `|mean| < 0.2`; `0.85 < sd < 1.15`; chi-square vs N(0,1) `< 100`;
   - read `/app/samples_t2.tsv` and assert: 20000 values; all in `[-6,6]`;
     `|mean| < 0.25`; `0.95 < sd < 1.35`; chi-square vs the Laplace CDF
     (bins of width 0.3) `< 120`.
   Then run `python3 -m pytest /app/tests -q` — everything must pass.

## Deliverables / success criteria

- `/app/ars.R` contains a correct generic adaptive rejection sampler
  (`/app/status.txt` says `PASS`).
- `/app/samples_t1.tsv` and `/app/samples_t2.tsv` exist and are reproducible.
- `/app/tests/test_sampler.py` exists, covers both T1 and T2, and passes
  `pytest`.

The verifier independently re-runs the sampler from your `/app/ars.R` on both
targets with its own seeds and re-checks the same statistics, and requires
your pytest suite (which must reference both sample files) to exist and pass.
Do not modify `evaluate.R`, `target.R`, or the sample-output paths.