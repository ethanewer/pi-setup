# Fit a linear model with Bayesian MCMC (numpy)

This environment has `numpy` installed (no other libraries are required).

`/app/data.json` holds a small dataset:

```json
{"x": [ ... 25 numbers ... ], "y": [ ... 25 numbers ... ]}
```

The relationship is approximately linear, `y ≈ a + b·x`, with a small deterministic wobble. Your job is to fit a linear regression **with Bayesian inference via MCMC sampling** and report the Bayesian posterior mean of the slope `b`.

## Model

Use the following probabilistic model:

- likelihood: `y_i ~ Normal(a + b·x_i, sigma)` for each data point `i`
- priors: `a ~ Normal(0, 10)`, `b ~ Normal(0, 10)`, `sigma ~ HalfCauchy(2)` (i.e. `sigma = |z|` with `z ~ Cauchy(0, 2)`)

## What to do

1. Write a Python script `/app/fit.py` that implements an MCMC sampler (e.g. a random-walk Metropolis–Hastings sampler) for this model using only `numpy`:

   - load `/app/data.json` (`x` and `y` arrays),
   - set a **fixed random seed** (e.g. `np.random.RandomState(123)`) so the run is deterministic,
   - sample the posterior over `(a, b, sigma)` — propose new values from a Normal centered on the current value, accept/reject with the log-posterior ratio (log-likelihood + log-prior);
   - use a reasonable number of iterations (e.g. 30000) and discard a burn-in (e.g. the first 5000) before recording samples;
   - compute `b_mean = mean` of the recorded `b` samples.

   A compact sketch (fill in the details correctly):

   ```python
   import json, numpy as np
   d = json.load(open('/app/data.json'))
   x = np.asarray(d['x'], dtype=float)
   y = np.asarray(d['y'], dtype=float)
   N = len(x)
   rng = np.random.RandomState(123)
   # ... random-walk MH over (a, b, log sigma) ...
   b_mean = ...   # posterior mean of the slope
   ```

2. Run `/app/fit.py` (`python3 /app/fit.py`) and write `/app/result.txt` with exactly one line:

```
b_mean=<b_mean rounded to 3 decimal places>
```

The verifier reads `/app/result.txt`, extracts the number after `b_mean=`, and requires it to be within `0.25` of the true slope value `1.7`.

## Note
- The answer must come from actual MCMC sampling of the posterior above — do not hardcode the output.
- Keep the sampler deterministic (fixed seed) so the result is reproducible.
- Do not change `/app/data.json`.