#!/bin/bash
set -euo pipefail

cat > /app/gemm.py <<'PYEOF'
import json
import numpy as np

A = np.array([[1, 2], [3, 4]])
B = np.array([[5, 6], [7, 8]])
C = (A @ B).tolist()

with open('/app/product.json', 'w') as f:
    json.dump({'C': C}, f)
PYEOF

python3 /app/gemm.py
echo "wrote /app/product.json"