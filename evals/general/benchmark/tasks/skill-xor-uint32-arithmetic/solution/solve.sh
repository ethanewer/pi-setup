#!/bin/bash
set -euo pipefail

cat > /app/proc.py <<'EOF'
import json

with open("/app/data.json") as f:
    d = json.load(f)
a = d["a"]
b = d["b"]
MASK = 0xFFFFFFFF

out = {
    "a": a,
    "b": b,
    "sum_wrapped": (a + b) & MASK,
    "xor": a ^ b,
}
with open("/app/result.json", "w") as f:
    json.dump(out, f)
EOF

python3 /app/proc.py