#!/bin/bash
set -euo pipefail
cat > /app/eigens.py <<'PY'
import numpy as np
M = np.loadtxt('/app/matrix.txt')
vals, vecs = np.linalg.eig(M)
idx = int(np.argmax(np.real(vals)))
lam = np.real(vals[idx])
v = np.real(vecs[:, idx])
v = v / np.linalg.norm(v)
sv = sorted(np.real(vals))
with open('/app/eigen.txt', 'w') as f:
    f.write(f"eigenvalues {sv[0]:.6f} {sv[1]:.6f}\n")
    f.write(f"dominant {lam:.6f}\n")
    f.write(f"eigenvector {v[0]:.12f} {v[1]:.12f}\n")
PY
python3 /app/eigens.py