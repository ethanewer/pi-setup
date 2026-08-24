# Item-001 (medium) — Adaptive rejection sampling in R

You are a statistical programmer working on a Monte-Carlo package. The research
team needs i.i.d. samples from an **unnormalized, log-concave** probability
density, and the tool of choice is **adaptive rejection sampling (Gilks &
Wild)**.

## Files already in the container

- `/app/target.R` — defines the target density for this task:
  - `log_fun(x)`: the log of an unnormalized log-concave density, namely a
    standard Normal restricted to `[-4, 4]` (`-0.5*x^2` inside the support,
    `-Inf` outside). It is vectorizable.
  - `log_deriv(x)`: the derivative of `log_fun`, i.e. `-x`. Also vectorizable.
- `/app/ars.R` — declares `ars_sample(log_fun, log_deriv, left, right, n, seed)`
  which is *supposed* to return a length-`n` numeric vector sampled from the
  target via adaptive rejection sampling. The current implementation is
  defective: the samples it produces are **not** distributed N(0,1).
- `/app/evaluate.R` — the evaluator. It calls your `ars_sample`, writes the
  samples to `/app/samples.tsv` (one number per line), and checks:
  1. sample mean ≈ 0,
  2. sample standard deviation ≈ 1,
  3. a histogram chi-square statistic vs. the N(0,1) distribution (must be
     < 150).
  It prints a per-check report and finishes with `PASS` / `FAIL`, and writes
  the verdict to `/app/status.txt`.

## What to do (work in stages)

1. **Read the contract.** Understand what `log_fun`/`log_deriv` provide, what
   `ars_sample` must return, and what `evaluate.R` checks.
2. **Run the evaluator** to see where things stand:

   ```bash
   cd /app && Rscript evaluate.R
   ```

   It will report which statistical checks fail.
3. **Fix `/app/ars.R`** so `ars_sample` performs genuine adaptive rejection
   sampling from the given log-concave target. Requirements:
   - The function signature and the return type (length-`n` numeric vector)
     must not change.
   - It must build a piecewise-linear upper envelope (tangent hull) around
     `log_fun`, sample from the resulting piecewise-exponential proposal, and
     accept/reject against the true density. A point is added to the knot set
     when it is rejected, refining the envelope (the “adaptive” part).
   - It may assume `log_fun` is log-concave on `[left, right]`.
   - The seeded results must be reproducible via the `seed` argument (the
     function owns its own RNG as it does now).
4. **Iterate**: rerun `Rscript evaluate.R` until it prints `PASS`.
5. **Add statistical tests**: create `/app/tests/test_sampler.py`, a `pytest`
   test suite (pure Python standard library only — `math` is fine, do not
   require numpy) that reads `/app/samples.tsv` produced by running
   `Rscript evaluate.R` and asserts, with reasonable tolerances:
   - the file contains exactly 20000 numeric values,
   - all values lie inside `[-4, 4]`,
   - `|mean| < 0.15`,
   - `0.85 < sd < 1.15`,
   - a histogram chi-square goodness-of-fit against N(0,1) (bins of width 0.2
     over `[-4,4]`) is below 150, computed from the sample proportions.
   Then run `python3 -m pytest /app/tests -q` and make sure everything passes.

## Deliverables / success criteria

- `/app/ars.R` contains a correct adaptive rejection sampler (the verdict file
  `/app/status.txt` from `evaluate.R` says `PASS`).
- `/app/samples.tsv` exists with 20000 reproducible samples.
- `/app/tests/test_sampler.py` exists and passes `pytest`.

The verifier independently re-runs the sampler from your `/app/ars.R` with its
own seed and requires the output to pass the same statistical checks, and it
requires your pytest suite to exist and pass. Do not modify `evaluate.R`,
`target.R`, or their output paths.