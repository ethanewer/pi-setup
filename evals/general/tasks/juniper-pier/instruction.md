# Juniper Pier — Bayesian calibration workflow (PyStan + penalty selection)

You are working in the materials-science lab at **Kitrela Copper Alloys**. The
team calibrates a linear relationship between the applied **tension** (kN) on a
micro-specimen and the resulting **elongation** (%) using Bayesian MCMC. Their
existing fit was validated in R with **rstan**; you must now deliver a faithful
PyStan port plus a companion sparse-regression penalty selection.

You work in `/app`. Do **not** touch `/tests` or `/solution` (they are mounted
read-only / absent — you never see them). Leave the provided data files
untouched.

## What is already in `/app`

- `model.stan` — the calibration Stan model (intercept `alpha`, slope `beta` on
  `tension`, residual scale `sigma`). Do not change the model: your job is to
  *run it correctly*, not to re-specify it.
- `reference_rstan.yaml` — the sampling configuration the team uses in rstan.
- `data/calib.csv` — calibration data, columns `tension, elongation`
  (`elongation` = `alpha + beta*tension + noise`).
- `data/features.csv` — a separate tabular dataset for the penalized regression,
  columns `load, grain, heat, humidity, speed, stretch`. `stretch` is the target.

You must also parse/read `reference_rstan.yaml`. It has this format
(its exact rstan semantics matter):

```yaml
chains: 4          # number of MCMC chains in rstan
iter: 2400         # total iterations PER CHAIN (warmup INCLUDED)
warmup: 800        # warmup iterations per chain (discarded)
thin: 1
seed: 20260727
control:
  adapt_delta: 0.95
  max_treedepth: 10
  stepsize: 0.85
```

## The deliverable: `/app/posterior.py`

Write a single executable Python 3 script that does **three** things. It must be
re-runnable on brand-new CSV files with the **same schema** (this is how the
verifier tests it — do not hardcode file contents).

The relevant Python packages are installed already: `numpy`, `scipy`,
`pandas`, `scikit-learn`, and `pystan` (the PyStan 3 package — import it as
`import stan`). PyStan's `stan.build(program_code, data=..., random_seed=...)`
returns a model you sample with `model.sample(num_chains=, num_warmup=,
num_samples=)`. A sampled fit exposes `to_frame()`, whose columns include
`alpha`, `beta`, `sigma`.

### CLI contract (must match exactly)

- `python3 /app/posterior.py`
  runs both phases on the default `/app` datasets and writes every output file
  below.
- `python3 /app/posterior.py posterior --data=<file.csv> [--out=<json>] [--draws=<csv>]`
  → runs ONLY the posterior phase on the given data; writes the mean summary to
  `--out` (default `/app/posterior_means.json`) and the raw draws to `--draws`
  (default `/app/posterior.csv`).
- `python3 /app/posterior.py penalty --data=<file.csv> [--out=<txt>] [--model-cmp=<csv>]`
  → runs ONLY the penalty-selection phase; prints the chosen penalty (a single
  number) to stdout, writes it to `--out` (default `/app/penalty.txt`), and
  writes the comparison rows to `--model-cmp` (default
  `/app/model_comparison.csv`).

### Required artifacts (all must be written by running `/app/posterior.py`)

1. `/app/hparams.json` — the faithful **rstan→pystan hyperparameter map** (see below).
2. `/app/posterior_means.json` — the posterior run summary (below).
3. `/app/posterior.csv` — the posterior draws (`alpha,beta,sigma`), one row per draw.
4. `/app/penalty.txt` — the chosen regularization penalty (a single number).
5. `/app/model_comparison.csv` — model-comparison rows (below).

## Phase A — posterior sampling (the rstan/pystan workflow)

- **Read** `reference_rstan.yaml` at runtime. **Port the sampling hyperparameters
  to PyStan semantics** and record them in `/app/hparams.json` with these keys:
  - `source` = `"reference_rstan.yaml"`
  - `num_chains`, `num_warmup`, `num_samples`, `thin`, `seed`
  - `adapt_delta`, `max_treedepth`, `stepsize` (from the `control:` block)

  ⚠️ **Critical semantics (this is the trap):** in rstan, `iter` is the **total**
  per-chain iteration count and it *includes* the `warmup` phase, so the sampling
  phase per chain is `num_samples = iter - warmup`. PyStan's `num_samples` is
  precisely that post-warmup (sampling) phase, and `num_warmup` is the adaptive
  warmup. Setting `num_warmup` to the *total* `iter` (or otherwise mis-allocating
  warmup vs. sample) discards the wrong number of draws and shifts the reported
  posterior means — that is what we test for.

- Build the model from `/app/model.stan` with `stan.build(...,
  random_seed=<seed from config>)` and sample with `num_chains`, `num_warmup`,
  `num_samples` taken from the translated map. This is the deterministic run.
- Write `/app/posterior_means.json`:
  ```json
  {
    "alpha": <float>, "beta": <float>, "sigma": <float>,
    "num_chains": 4, "num_warmup": 800, "num_samples": 1600,
    "thin": 1, "seed": 20260727,
    "effective_total_draws": 6400, "data_rows": <n>
  }
  ```
  where `alpha`,`beta`,`sigma` are the posterior means over all chains/samples of
  those parameters, and `effective_total_draws = num_chains * num_samples`.

### Output formats (tested byte-by-byte by the verifier)

- All JSON numeric values are plain JSON floats/ints (no rounding issues beyond
  Python's default float representation). Non-whitespace keys/ordering are
  unimportant; the **set of keys** and their **values** are what get checked.
- `/app/posterior.csv` must be parseable by `pandas.read_csv` and contain columns
  `alpha,beta,sigma` with exactly `num_chains * num_samples` rows after the header
  (no missing/NaN rows). The means of those columns must equal the means reported
  in `posterior_means.json`.
- `/app/penalty.txt` contains **only** the chosen penalty on the first line
  (a positive floating-point literal, e.g. `0.017236`). No header is added.
- `/app/model_comparison.csv` is CSV with at least columns `variant,penalty,dof,criterion`
  and exactly the three rows named `lasso_cv`, `lasso_aicc`, `ridge_cv`, with
  their chosen penalties as real numbers. The three penalty values must **not** be
  identical to one another (they probe genuinely different estimator paths), and
  the `ridge_cv` penalty must differ from the reported lasso penalty.

### Acceptance criteria (probed on the default data AND on hidden datasets)

- **Faithfulness:** `num_chains == chains`, `num_warmup == warmup`,
  `num_samples == iter - warmup`, `seed == seed` from the reference config; and
  `num_samples != warmup` (i.e. the samples vs warmup are not conflated).

- **Posterior accuracy:** For calibration data generated from a known
  `(alpha, beta)`, the posterior means must be within **0.25** of the true
  generating values. On the default `data/calib.csv` the true values are
  **alpha = `-0.4`** and **beta = `1.5`**.
- **Determinism:** run Phase A twice with the reference seed; the reported mean
  `alpha` and `beta` must agree to within `1e-3`.
- **Penalty corroboration:** the chosen penalty must be corroborated by *two
  independent scoring criteria*: cross-validation and a **corrected information
  criterion (AICc)**. Concretely, if `lam_cv` is the CV-selected
  `LassoCV.alpha_` and `lam_aic` is the AICc-optimal penalty, then the reported
  penalty must lie inside `[min(lam_cv,lam_aic)*0.6, max(lam_cv,lam_aic)*1.6]`
  and the criteria must agree to within a factor of 10:
  `max(lam_cv,lam_aic) / min(lam_cv,lam_aic) <= 10`.

  The AICc used is
  `AICc = n*ln(RSS/n) + 2k + 2k(k+1)/(n - k - 1)`,
  where `RSS` is the residual sum of squares of a `Lasso` fit at that penalty and
  `k` is its number of non-shrunk coefficients (≈ count of `|coef| > 1e-8`).
  Ridge penalty is chosen with `RidgeCV`.

## Runtime expectations

- The posterior run compiles the Stan model live (httpstan backend); the first
  compile inside a container takes ~10–30 s, then is cached. Keep the model the
  simple linear one in `model.stan`. Do not increase the sample counts beyond the
  reference config's `num_samples`; the verifier re-runs Phase A inside a time
  budget.
- Do not read or write outside `/app` except in `/tmp` (scratch). Do not modify
  `model.stan`, the `data/*.csv` files, or `reference_rstan.yaml`.
- Exit status `0` on success. If a data CSV is malformed or a phase cannot
  complete, print a clear error and exit non-zero (rather than writing
  half/corrupt outputs).

Work by editing/writing files with the tools in `/app` and then actually
runnning `/app/posterior.py` so all five artifacts are produced by a real run —
do not hand-write `posterior_means.json`, `posterior.csv`, `penalty.txt`, or
`hparams.json`. Those four files are produced as a **side-effect of running** the
program, never by copying.