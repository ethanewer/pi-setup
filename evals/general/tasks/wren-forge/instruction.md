# Greenfield germination trials — hierarchical beta-binomial in Stan

Greenfield Labs runs seed-germination trials in several greenhouse batches.
Germination propensity varies from batch to batch, so the lab models the
per-batch success rates hierarchically: each batch has its own germination
probability `theta[g]`, the `theta[g]` are drawn from a shared **Beta(alpha,
beta)** population distribution, and the hyperparameters `(alpha, beta)`
carry a **Jeffreys-type hyper-prior**. You will author this Stan model and a
driver that fits it. Work in `/app`. **Do not modify**
`/app/trials.csv`, and never read `/tests`.

## Deliverables (all four required, all under `/app`)

1. `/app/hier_model.stan` — the Stan program (contract below).
2. `/app/fit.R` — an executable Rscript driver (contract below).
3. `/app/posterior.csv` — posterior draws for the **visible** data, written by
   running `/app/fit.R` (see below). Do not hand-author it.
4. `/app/summary.json` — the posterior summary for the **visible** data,
   written by the same run. Do not hand-author it.

## 1. The Stan program (`/app/hier_model.stan`)

The program must encode, exactly:

- **data block**: `int<lower=1> G;` the number of batches; `array[G]
  int<lower=1> n;` the per-batch trial counts; `array[G] int<lower=0> k;` the
  per-batch germination counts.
- **parameters**: `alpha > 0`, `beta > 0` (the shared Beta population
  hyperparameters) and a per-batch probability vector
  `vector<lower=0,upper=1>[G] theta`.
- **model block** with, in this order of intent:
  1. the **Jeffreys-type hyper-prior** over the `(alpha, beta)` pair, written
     with this exact term (spacing may differ, the arithmetic may not):

     ```
     target += -0.5 * log(alpha) - 0.5 * log(beta) - 0.5 * log(alpha + beta);
     ```

  2. the **shared beta group prior**: `theta ~ beta(alpha, beta);`
  3. the **per-group binomial likelihood**: `k ~ binomial(n, theta);`

No other priors on `alpha`/`beta`/`theta` (no flat `alpha ~ uniform(...)` on
top, no `theta` fixed to the empirical rates). The program must parse and
compile with rstan without error and sample successfully.

## 2. The driver (`/app/fit.R`)

Must run as:

```
Rscript /app/fit.R <trials.csv> <outdir>
```

(exactly two arguments; never rely on the current working directory or on the
visible data by name). Behavior:

1. Read the CSV. Header exactly `batch,trials,germinated`. Validate: at least
   **2** rows (groups), every `trials` a positive integer, every `germinated`
   an integer with `0 <= germinated <= trials`. On any violation print a clear
   error to stderr and **exit non-zero** without writing outputs.
2. Write the **exact Stan program** of deliverable 1 to
   `<outdir>/hier_model.stan` (the driver must contain/embed the program it
   fits — do not read it from elsewhere).
3. Compile the program with rstan (`stan_model`) and sample with rstan
   `sampling` using **`seed = 20240607`**, `chains = 2`, `warmup = 400`,
   `iter = 1000` (i.e. 600 post-warmup draws per chain, 1200 total). This
   makes the run deterministic on this machine.
4. Write `<outdir>/posterior.csv` — one row per posterior draw (1200 rows),
   header `theta1,theta2,...,thetaG,alpha,beta`, no row-name column.
5. Write `<outdir>/summary.json` with exactly these keys:

   ```json
   {
     "groups": 6,
     "batch_ids": ["AUR-1", "..."],
     "theta_mean": [0.0, ...],
     "alpha_mean": 0.0,
     "beta_mean": 0.0,
     "n_draws": 1200,
     "seed": 20240607
   }
   ```

   (`groups` = number of CSV rows, `batch_ids` in file order, `theta_mean` =
   per-batch posterior means in batch order, `n_draws` = total post-warmup
   draws, `seed` = 20240607.)
6. Print one line containing `FIT_OK` to stdout and exit 0.

The visible-case deliverables are produced by:

```
Rscript /app/fit.R /app/trials.csv /app
```

## What the grader does

- It **re-runs `/app/fit.R` unchanged** on the visible data and on fresh
  hidden trial tables (different batch counts, sizes and rates), so the
  driver and the Stan program must be fully general — no hard-coded group
  counts, batch ids, or rates.
- It **independently compiles `/app/hier_model.stan`** with rstan and samples
  it itself, checking that the posterior per-batch means actually track the
  empirical germination rates (which a model without the binomial likelihood
  or with the wrong prior structure cannot do), and that `alpha`/`beta` are
  strictly positive. The Jeffreys-type hyper-prior term is checked in the
  source.
- It checks that `<outdir>/hier_model.stan` written by a run is byte-identical
  to `/app/hier_model.stan`, that `posterior.csv` has the exact header and a
  full set of draws, and that `summary.json` matches a fresh regeneration.

## Requirements / gotchas

- `library(rstan)` must load without error; rstan compiles the Stan model at
  runtime with the system C++ toolchain (the first compile takes on the order
  of a minute — that is expected). Keep the documented iteration counts so a
  full run stays bounded.
- `summary.json` must be valid JSON (use `jsonlite::toJSON` with
  `auto_unbox = TRUE` and write it as a file).
- No network access is needed at run time; do not add any.
