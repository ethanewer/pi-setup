#!/bin/bash
set -euo pipefail

cat > /app/cosim.py <<'PYEOF'
import json, math

a = json.load(open('/app/a.json'))
b = json.load(open('/app/b.json'))

def norm(v):
    return math.sqrt(sum(x*x for x in v))

na = norm(a)
nb = norm(b)
if na == 0 or nb == 0:
    c = 0.0
else:
    c = sum(x*y for x, y in zip(a, b)) / (na * nb)

with open('/app/sim.txt', 'w') as f:
    f.write("{:.6f}\n".format(c))
PYEOF

python3 /app/cosim.py