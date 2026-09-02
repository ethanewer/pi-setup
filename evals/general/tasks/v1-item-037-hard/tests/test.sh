#!/bin/bash
mkdir -p /logs/verifier
reward=0
if python3 - <<'PYEOF'
import json
import numpy as np
data = json.load(open('/app/matrix.json'))
A = np.array([[complex(r['re'], r['im']) for r in row] for row in data])
got = json.load(open('/app/eig.json'))
ev = [complex(e['re'], e['im']) for e in got['eigenvalues']]
V = np.array([[complex(c['re'], c['im']) for c in col] for col in got['eigenvectors']], dtype=complex).T
assert V.shape == (6, 6)
for i in range(6):
    v = V[:, i]
    nrm = np.linalg.norm(v)
    assert abs(nrm - 1.0) < 1e-6, nrm
    assert np.linalg.norm(A @ v - ev[i] * v) < 1e-6, i
ref_ev, _ = np.linalg.eig(A)
ref_ev = sorted(ref_ev, key=lambda z: (z.real, -abs(z.imag)))
mine = sorted(ev, key=lambda z: (z.real, -abs(z.imag)))
for a, b in zip(ref_ev, mine):
    assert abs(a - b) < 1e-7, (a, b)
PYEOF
then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt