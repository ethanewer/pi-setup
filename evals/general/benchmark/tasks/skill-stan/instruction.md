# Bayesian posterior inference with an MCMC sampler

This environment has **NumPy** available. `/app/data.json` holds a small dataset:

```json
{"N": 10, "y": [10.1, 9.8, 10.3, 9.9, 10.2, 9.7, 10.0, 9.9, 10.1, 10.0]}
```

The samples are centered near `10.0`. Fit a simple **normal model** with priors
`mu ~ N(0, 10)`, `sigma ~ Cauchy(0, 2)`, and likelihood `y ~ N(mu, sigma)`, then
report the Bayesian posterior mean of the location parameter `mu`.

1. Write a Python script `/app/fit.py` that:

   - loads `/app/data.json` (the `y` values) with `json`,
   - implements a **Metropolis–Hastings** (or other MCMC) sampler over `(mu, sigma)`
     targeting the unnormalized posterior density `log(p(mu)) + log(p(sigma)) +
     log-likelihood(y | mu, sigma)`, using `numpy.random` with a fixed seed (e.g. `42`)
     for determinism,
   - discards an initial burn-in and draws at least 2000 post-burn samples of `mu`,
   - computes `mu_mean = float(np.mean(mu_draws))`.

2. Write `/app/result.txt` with exactly one line:

```
mu_mean=<mu_mean rounded to 3 decimal places>
```

e.g. `mu_mean=10.000`.

The verifier reads the number after `mu_mean=` and requires it to be within `0.3`
of the true Bayesian posterior mean of `mu` (which is very close to the data mean
`10.0`).

## Notes
- Do not change `/app/data.json`.
- You must actually run an MCMC sampler you implemented; do not merely report the
  arithmetic sample mean from a closed-form shortcut.
- Use a long-enough chain and reasonable proposal step sizes so the posterior mean
  is accurate to well within `0.3`.