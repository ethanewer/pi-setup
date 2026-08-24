#!/bin/bash
# Oracle solution for skill-numpy.
set -euo pipefail

cat > /app/matmul.py <<'PYEOF'
import numpy as np

A = np.loadtxt('/app/A.txt', dtype=int)
B = np.loadtxt('/app/B.txt', dtype=int)

C = np.rint(A @ B).astype(int)
D = A + B

with open('/app/result.txt', 'w') as f:
    f.write('C:\n')
    for row in C:
        f.write(' '.join('%d' % x for x in row) + '\n')
    f.write('D:\n')
    for row in D:
        f.write(' '.join('%d' % x for x in row) + '\n')
PYEOF

python3 /app/matmul.py