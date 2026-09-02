# item-043 workbench

Same model and data as described in the main README contract, plus:

- `/app/fit_rstan.R` is SHIPPED but **subtly broken on purpose**: inspect its
  `summary`/diagnostics output to find and fix every defect so it satisfies
  the contract (all 8 parameters in the summary, `iter`/`warmup` adequate for
  the diagnostics thresholds below, seed 42).
- You must also write `/app/fit_pystan.py` (PyStan 3.10; contract above in
  `solve` folder / `README` summary fields).
- `fit_pystan.py` must additionally write `/app/ppc.json`:
  `{"mean_y":..,"sd_y":..,"mean_y_rep":..,"sd_y_rep":..}` computed from the
  posterior predictive draws `y_rep`.
