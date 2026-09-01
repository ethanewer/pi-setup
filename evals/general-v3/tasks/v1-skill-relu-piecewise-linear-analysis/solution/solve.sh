#!/usr/bin/env bash
set -euo pipefail
cat > /app/relu.py <<'PY'
import json

d = json.load(open('/app/data.json'))
x = d["x"]; W1 = d["W1"]; b1 = d["b1"]; W2 = d["W2"][0]; b2 = d["b2"][0]

z1 = [W1[0][0]*x[0] + W1[0][1]*x[1] + b1[0],
      W1[1][0]*x[0] + W1[1][1]*x[1] + b1[1]]
h = [max(0.0, v) for v in z1]
active = [v > 0 for v in h]
y = W2[0]*h[0] + W2[1]*h[1] + b2

json.dump({
    "hidden_pre": z1,
    "hidden_post": h,
    "active": active,
    "output": y,
}, open('/app/result.json', 'w'))
PY
python3 /app/relu.py
