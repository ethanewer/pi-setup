#!/bin/bash
mkdir -p /logs/verifier
reward=0

if python3 - <<'PY'
import numpy as np
M = np.loadtxt('/app/matrix.txt')
vals, vecs = np.linalg.eig(M)

lines = [l.strip() for l in open('/app/eigen.txt') if l.strip()]
assert len(lines) == 3, lines

ev = lines[0].split()[1:]
assert len(ev) == 2
got = sorted(float(x) for x in ev)
exp = sorted(np.real(vals))
assert all(abs(a - b) < 1e-3 for a, b in zip(got, exp)), (got, exp)

lam = float(lines[1].split()[1])
assert abs(lam - exp[1]) < 1e-3, lam

parts = lines[2].split()[1:]
assert len(parts) == 2
v = np.array([float(x) for x in parts])
assert abs(np.linalg.norm(v) - 1.0) < 1e-3, v
assert np.allclose(M @ v, lam * v, atol=1e-3), (M @ v, lam * v)
PY
then
  reward=1
fi

echo "$reward" > /logs/verifier/reward.txt