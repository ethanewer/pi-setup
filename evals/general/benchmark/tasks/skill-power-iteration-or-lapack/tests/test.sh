#!/bin/bash
mkdir -p /logs/verifier
reward=0
if python3 - <<'PYEOF'
import math
A = [[4.0, 1.0], [1.0, 3.0]]
_v = [1.0, 1.0]
for _ in range(3000):
    nv = [sum(A[i][j] * _v[j] for j in range(2)) for i in range(2)]
    norm = math.sqrt(sum(x * x for x in nv))
    _v = [x / norm for x in nv]
Av = [sum(A[i][j] * _v[j] for j in range(2)) for i in range(2)]
lam = sum(Av[i] * _v[i] for i in range(2)) / sum(_v[i] * _v[i] for i in range(2))
got = float(open('/app/eigenvalue.txt').read().strip())
assert abs(got - lam) <= 1e-3, (got, lam)
PYEOF
then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt