#!/bin/bash

mkdir -p /logs/verifier

reward=0

run_ok() {
  python3 - <<'PY'
import json, sys
import numpy as np

# independent recomputation of the expected values from the fixed inputs
mu = np.loadtxt('/app/mu.txt')
cov = np.loadtxt('/app/cov.txt')
w = np.loadtxt('/app/w.txt')
ref_ret = float(mu @ w)
ref_var = float(w @ (cov @ w))

# the extension must exist and its recomputation must match
try:
    import importlib, sys as s
    s.path.insert(0, '/app')
    import native
    cov_flat = cov.flatten().tolist()
    r = native.eval(mu.tolist(), cov_flat, w.tolist(), int(len(mu)))
    fast_ret = float(r[0]); fast_var = float(r[1])
except Exception:
    sys.exit(1)

if abs(fast_ret - ref_ret) / max(1.0, abs(ref_ret)) > 1e-6:
    sys.exit(1)
if abs(fast_var - ref_var) / max(1.0, abs(ref_var)) > 1e-6:
    sys.exit(1)

try:
    rep = json.load(open('/app/out/report.json'))
except Exception:
    sys.exit(1)

if rep.get('match') is not True:
    sys.exit(1)
if abs(rep['fast_ret'] - fast_ret) > 1e-9 or abs(rep['fast_var'] - fast_var) > 1e-9:
    sys.exit(1)
if not isinstance(rep.get('speedup'), (int, float)):
    sys.exit(1)
if not isinstance(rep.get('ref_sec'), (int, float)) or not isinstance(rep.get('fast_sec'), (int, float)):
    sys.exit(1)
if not (0.0 <= rep.get('speedup', 0)):
    sys.exit(1)

sys.exit(0)
PY
}

if [ -f /app/out/report.json ]; then
  if run_ok; then
    reward=1
  else
    reward=0
  fi
fi

echo "$reward" > /logs/verifier/reward.txt