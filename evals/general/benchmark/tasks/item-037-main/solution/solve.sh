#!/bin/bash
set -euo pipefail

mkdir -p /app/out

python3 - <<'PY'
import json
import numpy as np

A = np.loadtxt('/app/data/matrix.txt', dtype=float).reshape(5, 5)

evals, evecs = np.linalg.eig(A)
i = int(np.argmax(np.abs(evals)))
lam = evals[i]
v = np.real_if_close(evecs[:, i], tol=1e9).astype(float)
v = v / np.linalg.norm(v)
resid = float(np.linalg.norm(A @ (v.astype(complex)) - (lam * v.astype(complex))))

out = {
    "lambda": float(np.real(lam)) if np.isclose(np.imag(lam), 0, atol=1e-9) else float(lam),
    "eigenvector": [float(x) for x in v],
    "residual": resid,
}
with open('/app/out/eigen.json', 'w') as f:
    json.dump(out, f)
print("eigenpair computed", out["lambda"])
PY