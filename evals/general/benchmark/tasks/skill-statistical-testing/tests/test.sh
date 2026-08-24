#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/stats.txt ]; then
  python3 - <<'PY' && reward=1
import numpy as np
from scipy import stats

A = np.array([12.1, 13.0, 11.8, 12.7, 12.4])
B = np.array([14.2, 13.9, 15.1, 14.0, 13.7])
exp_t, exp_p = stats.ttest_ind(A, B)
table = np.array([[5, 12, 8], [6, 9, 10]])
exp_chi2, exp_p2, dof, expected = stats.chi2_contingency(table)

expected_vals = {
    'ttest_stat': round(float(exp_t), 6),
    'ttest_p': round(float(exp_p), 6),
    'chi2_stat': round(float(exp_chi2), 6),
    'chi2_p': round(float(exp_p2), 6),
}

lines = [ln.strip() for ln in open('/app/stats.txt') if ln.strip()]
assert len(lines) == 4, lines
got = {}
for ln in lines:
    k, _, v = ln.partition('=')
    got[k.strip()] = float(v)

assert set(got) == set(expected_vals), (set(got), set(expected_vals))
for k, ev in expected_vals.items():
    assert abs(got[k] - ev) <= 1e-5, (k, got[k], ev)
PY
fi
echo "$reward" > /logs/verifier/reward.txt