#!/bin/bash
set -euo pipefail

cat > /app/stats.py <<'PY'
import numpy as np
from scipy import stats

A = np.array([12.1, 13.0, 11.8, 12.7, 12.4])
B = np.array([14.2, 13.9, 15.1, 14.0, 13.7])
t, p = stats.ttest_ind(A, B)

table = np.array([[5, 12, 8],
                  [6, 9, 10]])
chi2, p2, dof, expected = stats.chi2_contingency(table)

with open('/app/stats.txt', 'w') as f:
    f.write(f"ttest_stat={round(float(t), 6):.6f}\n")
    f.write(f"ttest_p={round(float(p), 6):.6f}\n")
    f.write(f"chi2_stat={round(float(chi2), 6):.6f}\n")
    f.write(f"chi2_p={round(float(p2), 6):.6f}\n")
PY

python3 /app/stats.py