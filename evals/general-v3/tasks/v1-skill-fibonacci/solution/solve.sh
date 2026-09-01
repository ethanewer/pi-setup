#!/bin/bash
set -euo pipefail

cat > /app/fib.py <<'PYEOF'
import json

with open('/app/n.txt') as f:
    n = int(f.read().strip())

a, b = 0, 1
for _ in range(n):
    a, b = b, a + b
# after loop, a == F(n)

with open('/app/fib.json', 'w') as f:
    json.dump({'n': n, 'value': a}, f)
PYEOF

python3 /app/fib.py