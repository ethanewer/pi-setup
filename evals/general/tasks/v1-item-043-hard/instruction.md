# Fit the hierarchical GP model with BOTH RStan and PyStan (hard)

Same setup as the **main** task (model.stan, data.csv, the full I/O contract in
`README.md`), but with one adversarial twist:

**`/app/fit_rstan.R` is shipped broken.** It has several subtle defects with respect to the
contract (wrong `pars` vector, too-short warmup, seed, ...). Your job:
- Run it, inspect its `rstan_summary.csv` / `rstan_diag.json` diagnostics,
  find **every** defect,
- fix `/app/fit_rstan.R` so it satisfies the whole contract (all 8
  parameters in the summary; adequate iterations; seed 42),
- also write `/app/fit_pystan.py` (PyStan 3.10) following the same contract, writing
  `pystan_summary.csv` / `pystan_diag.json`, plus `/app/ppc.json` posterior-predictive
  sanity: `{"mean_y":..., "sd_y":..., "mean_y_rep":..., "sd_y_rep":...}`.

Verifier thresholds (hard): `rhat <= 1.10`, `n_eff >= 100`, `divergent == 0`,
cross-stack tolerance `0.5 * pooled_sd` below, and PPC must satisfy
`0.75 <= mean_ratio <= 1.25` and `0.5 <= sd_ratio <= 2.0`.

Same deterministic data/model; seed 42 on both stacks (the reference and PyStan).