#!/bin/bash
set -euo pipefail

cat > /app/forward.py <<'EOF'
import json
import numpy as np

x = np.array(json.load(open('/app/input.json'))['x'])
sa = json.load(open('/app/shard_a.json'))
sb = json.load(open('/app/shard_b.json'))
W1 = np.array(sa['W1']); b1 = np.array(sa['b1'])
W2 = np.array(sb['W2']); b2 = np.array(sb['b2'])

h = W1 @ x + b1
y_layer = W2 @ h + b2

Wc = W2 @ W1
bc = b2 + W2 @ b1
y_composed = Wc @ x + bc

max_diff = float(np.max(np.abs(y_layer - y_composed)))
out = {
    "y_layer": [round(float(v), 4) for v in y_layer],
    "y_composed": [round(float(v), 4) for v in y_composed],
    "max_diff": round(max_diff, 6),
}
with open('/app/forward_check.json', 'w') as f:
    json.dump(out, f)
EOF
python3 /app/forward.py