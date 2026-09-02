#!/bin/bash

mkdir -p /logs/verifier

reward=0

run_ok() {
python3 - <<'PY'
import json, sys
import numpy as np

A = np.loadtxt('/app/data/matrix.txt', dtype=float).reshape(5, 5)

try:
    d = json.load(open('/app/out/eigen.json'))
    lam_agent = complex(d['lambda'])
    v = np.asarray(d['eigenvector'], dtype=float)
except Exception as e:
    sys.exit(1)

if v.size < 5:
    sys.exit(1)
v = v[:5]
norm = np.linalg.norm(v)
if not (0.9999 < norm < 1.0001):
    sys.exit(1)

evals, _ = np.linalg.eig(A)
abs_e = np.abs(evals)
maxabs = float(np.max(abs_e))
i_ref = int(np.argmax(abs_e))
lam_ref = evals[i_ref]

# dominance: reported |lambda| is the largest-magnitude eigenvalue of A
if not np.isclose(abs(lam_agent), maxabs, rtol=1e-6, atol=1e-6):
    sys.exit(1)

# residual: A v ~= lambda v (objective, sign-independent)
resid = float(np.linalg.norm(A @ (v.astype(complex)) - (lam_agent * v.astype(complex))))
scale = max(1.0, abs(lam_agent))
if resid / scale > 1e-8:
    sys.exit(1)

# reported residual field need not be exact, but must be a float
if not isinstance(d.get('residual'), (int, float)):
    sys.exit(1)

sys.exit(0)
PY
}

if [ -f /app/out/eigen.json ]; then
  if run_ok; then reward=1; else reward=0; fi
fi

echo "$reward" > /logs/verifier/reward.txt