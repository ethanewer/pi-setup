#!/bin/bash
set -euo pipefail

cat > /app/deriv.py <<'EOF'
import json

with open('/app/xs.json') as f:
    xs = json.load(f)

def f(x):
    return x**3 - 2*x + 1

h = 0.01
out = []
for x in xs[1:-1]:
    d = (f(x+h) - f(x-h)) / (2*h)
    out.append(round(d, 3))

with open('/app/diffs.json','w') as f:
    json.dump(out, f)

print(out)
EOF
python3 /app/deriv.py