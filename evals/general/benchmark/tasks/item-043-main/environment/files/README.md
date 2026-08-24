# item-043 workbench

`/app/model.stan` — Stan program: a **hierarchical Gaussian-process
regression** (group-level intercepts `b_g` shrunk toward `b0` through `tau`,
plus a GP prior (`rho`, `alpha`) on a latent function `eta`, observation noise
`sigma`, and a posterior-predictive block `y_rep`).

`/app/data.csv` — observation data: columns `g` (group id, 1..3), `x`
(covariate in [0,1]), `y` (response).

I/O contract for the two scripts you must write (see instruction.md):

- `/app/fit_rstan.R` — RStan 2.32.x fit; writes
  `/app/rstan_summary.csv` with columns
  `param,mean,sd,lo,hi,rhat,n_eff` (one row per parameter, including `b_g[1]`
  .. `b_g[3]`; `lo`/`hi` are the 2.5%/97.5% percentiles) and
  `/app/rstan_diag.json`
  (`{"rhat_max":..., "n_eff_min":..., "divergent":...}`).
- `/app/fit_pystan.py` — PyStan 3.10 fit; writes the same two files with
  names `pystan_summary.csv`, `pystan_diag.json`.

Both must fit `/app/model.stan` with `/app/data.csv`, seed 42, and report the
full parameter set `rho, alpha, sigma, b0, tau, b_g[1], b_g[2], b_g[3]`.