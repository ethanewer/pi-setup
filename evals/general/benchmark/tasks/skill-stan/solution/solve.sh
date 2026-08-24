#!/bin/bash
set -euo pipefail

cat > /app/fit.py <<'PYEOF'
import json
import math
import numpy as np

with open('/app/data.json') as f:
    d = json.load(f)

y = np.array(d['y'], dtype=float)
n = y.size

rng = np.random.default_rng(42)

def log_target(mu, logsig):
    # unnormalized log posterior for:
    #   mu    ~ N(0, 10)
    #   sigma ~ Cauchy(0, 2)
    #   y     ~ N(mu, sigma)
    s = math.exp(logsig)
    if s <= 0.0:
        return -1e18
    lp = -0.5 * (mu / 10.0) ** 2                       # mu prior
    lp += -math.log(1.0 + (s / 2.0) ** 2)              # sigma cauchy kernel
    lp += -n * logsig - 0.5 * (((y - mu) ** 2).sum()) / (s * s)  # likelihood
    return lp

mu = float(y.mean())
logsig = math.log(max(float(y.std()), 1e-3))
cur = log_target(mu, logsig)

draws = []
N_ITER = 6000
BURN = 2000
for it in range(N_ITER):
    mu2 = mu + rng.normal(0.0, 0.4)
    ls2 = logsig + rng.normal(0.0, 0.6)
    a = log_target(mu2, ls2) - cur
    if math.log(rng.uniform()) < a:
        mu, logsig = mu2, ls2
        cur = log_target(mu, logsig)
    if it >= BURN:
        draws.append(mu)

mu_mean = float(np.mean(draws))
with open('/app/result.txt', 'w') as f:
    f.write(f"mu_mean={round(mu_mean, 3):.3f}\n")
PYEOF

python3 /app/fit.py