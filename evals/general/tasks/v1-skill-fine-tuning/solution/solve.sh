#!/bin/bash
set -euo pipefail

cat > /app/finetune.py <<'EOF'
import json

with open('/app/model.json') as f:
    m = json.load(f)
with open('/app/data.json') as f:
    d = json.load(f)

x = d["x"]; y = d["y"]
w, b = m["w"], m["b"]
lr = 0.1
N = len(x)

preds = [w * xi + b for xi in x]
errors = [p - yi for p, yi in zip(preds, y)]
grad_w = (2.0 / N) * sum(e * xi for e, xi in zip(errors, x))
grad_b = (2.0 / N) * sum(errors)

w_new = w - lr * grad_w
b_new = b - lr * grad_b

with open('/app/model_out.json','w') as f:
    json.dump({"w": round(w_new, 3), "b": round(b_new, 3)}, f)
EOF
python3 /app/finetune.py