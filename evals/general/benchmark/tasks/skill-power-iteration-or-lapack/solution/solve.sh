#!/bin/bash
set -euo pipefail

# Power iteration for the dominant eigenvalue of [[4,1],[1,3]].
python3 - <<'PY'
import math
A = [[4.0, 1.0], [1.0, 3.0]]
v = [1.0, 1.0]
for _ in range(3000):
    nv = [sum(A[i][j]*v[j] for j in range(2)) for i in range(2)]
    norm = math.sqrt(sum(x*x for x in nv))
    v = [x/norm for x in nv]
Av = [sum(A[i][j]*v[j] for j in range(2)) for i in range(2)]
lam = sum(Av[i]*v[i] for i in range(2)) / sum(v[i]*v[i] for i in range(2))
with open('/app/eigenvalue.txt', 'w') as f:
    f.write(f'{lam:.4f}\n')
print('dominant eigenvalue', lam)
PY