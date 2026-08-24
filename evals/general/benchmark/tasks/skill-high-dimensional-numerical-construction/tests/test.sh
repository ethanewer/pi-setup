#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/coeffs.txt ] && [ -f /app/regression.csv ]; then
  if python3 - <<'PYEOF'
import numpy as np, sys
data = np.genfromtxt('/app/regression.csv', delimiter=',', skip_header=1)
X = data[:, :5]; y = data[:, 5]
expected, *_ = np.linalg.lstsq(X, y, rcond=None)
try:
    got = np.array([float(x) for x in open('/app/coeffs.txt').read().split()])
except Exception:
    sys.exit(1)
if got.shape != expected.shape:
    sys.exit(1)
sys.exit(0 if np.all(np.abs(got - expected) <= 1e-3) else 1)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt