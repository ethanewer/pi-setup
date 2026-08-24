# Translate an RStan hierarchical GP regression to PyStan and validate it

`/app` holds a small Bayesian model workbench. A **hierarchical
Gaussian-process regression** is specified once, in Stan (`model.stan`), with
data in `data.csv` (columns `g`, `x`, `y`). You must fit the SAME model in
**two different language stacks**, translate the RStan invocation **exactly**
into the PyStan 3.10 API, and demonstrate—via MCMC diagnostics and posterior
comparison—that the translations preserve the model and prior semantics.

## Environment facts

- **RStan 2.32.7** (R) and **PyStan 3.10** (Python) are preinstalled; both
  compile the Stan program at first use (allow a few minutes; compile results
  are cached for reruns).
- `/app/model.stan` — GP regression w/ group intercepts: parameters `rho`,
  `alpha`, `sigma`, `b0`, `tau`, `b_g[1..3]`, latent `eta`; prior
  `b_g ~ normal(b0, tau)`; posterior predictive `y_rep`. Do not modify it.
- `/app/data.csv` — deterministic dataset (30 rows, 3 groups).
- `/app/README.md` — the I/O contract for your two scripts (read it).

## Your task

Write two scripts that each load `/app/data.csv`, fit `/app/model.stan`, and
emit (a) a summary CSV with columns `param,mean,sd,lo,hi,rhat,n_eff` (one row
per parameter: `rho, alpha, sigma, b0, tau, b_g[1], b_g[2], b_g[3]`; `lo`/`hi`
= 2.5%/97.5% percentiles) and (b) a diagnostics JSON
`{"rhat_max":..., "n_eff_min":..., "divergent":...}`:

- `/app/fit_rstan.R` — the RStan reference fit.
- `/app/fit_pystan.py` — the PyStan 3.10 translation. Semantics that MUST be
  preserved: identical data blocks, identical prior blocks (the same
  model.stan), identical sampling seed (42), identical number of chains and
  identical warmup/total iterations. Map the RStan invocation to
  `stan.build(...).sample(...)` ("map APIs across languages").

Use 2 chains, seed 42, and enough iterations (≥ 1000) to get clean
diagnostics. The verifier **reruns both scripts**, so they must be
self-contained and deterministic from seed 42.

## Success criteria (all scored by rerunning your scripts)

1. Both scripts run to completion and produce their summary CSV + diagnostics
   JSON (exact column/key formats above).
2. MCMC diagnostics pass for **all** core parameters, `rho alpha sigma b0 tau
   b_g[1..3]`: `rhat <= 1.15`, `n_eff >= 50`, and zero divergences.
3. The posterior summaries agree across the two stacks: for every parameter,
   `|mean_RStan - mean_PyStan| <= max(0.05, pooled_sd)` where `pooled_sd` is
   the mean of the two reported parameter sds.

Manage the compile/sample time sensibly (compile once, reuse the cached
model); if diagnostics are weak, increase iterations rather than chains.

Leave `/app/fit_rstan.R`, `/app/fit_pystan.py`, and their outputs
(`rstan_summary.csv`, `rstan_diag.json`, `pystan_summary.csv`,
`pystan_diag.json`) in `/app`.