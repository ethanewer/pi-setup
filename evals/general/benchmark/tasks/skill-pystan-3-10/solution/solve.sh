#!/bin/bash
set -euo pipefail

# Oracle solution: Bayesian linear regression via a deterministic
# random-walk Metropolis-Hastings sampler in numpy. Fixed seed -> reproducible.
cat > /app/fit.py <<'PY'
import json
import numpy as np

with open('/app/data.json') as f:
    d = json.load(f)

x = np.asarray(d['x'], dtype=float)
y = np.asarray(d['y'], dtype=float)
N = len(x)

rng = np.random.RandomState(123)

# Starting point: OLS estimate of (a, b) and residual s.d. for sigma
A = np.column_stack([np.ones(N), x])
a0, b0 = np.linalg.lstsq(A, y, rcond=None)[0]
s0 = float(np.std(y - (a0 + b0 * x)))

def log_post(a, b, log_sigma):
    s = np.exp(log_sigma)
    if not np.isfinite(s) or s <= 0 or s > 100:
        return -1e300
    # priors: a ~ N(0,10), b ~ N(0,10), sigma ~ HalfCauchy(2)
    lp = -0.5 * (a / 10.0) ** 2 - 0.5 * (b / 10.0) ** 2
    lp += -np.log(1.0 + (s / 2.0) ** 2)
    # likelihood: y_i ~ N(a + b x_i, sigma)
    resid = y - (a + b * x)
    lp += -N * np.log(s) - 0.5 * np.sum((resid / s) ** 2)
    return lp

a, b, ls = a0, b0, np.log(s0)
cur = log_post(a, b, ls)

ITERS = 30000
BURNIN = 5000
samples = []
for i in range(ITERS):
    na = a + 0.12 * rng.randn()
    nb = b + 0.12 * rng.randn()
    nls = ls + 0.15 * rng.randn()
    nlp = log_post(na, nb, nls)
    if nlp > cur or rng.rand() < np.exp(nlp - cur):
        a, b, ls, cur = na, nb, nls, nlp
    if i >= BURNIN:
        samples.append(b)

b_mean = float(np.mean(samples))
with open('/app/result.txt', 'w') as f:
    f.write(f'b_mean={b_mean:.3f}\n')
PY

python3 /app/fit.py
echo "wrote /app/result.txt"