#!/bin/bash
set -euo pipefail
cat > /app/solve.py <<'EOF'
import json
import autograd.numpy as np
from autograd import grad

def f(x, y):
    return x**2 * y + np.cos(x)

gx = grad(f, 0)(2.0, 3.0)
gy = grad(f, 1)(2.0, 3.0)
with open('/app/answer.json', 'w') as fh:
    json.dump({'df_dx': float(gx), 'df_dy': float(gy)}, fh)
EOF
python3 /app/solve.py
echo "wrote answer.json"