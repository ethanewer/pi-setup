#!/bin/bash
set -euo pipefail

cat > /app/decode.py <<'EOF'
import json

rle = json.load(open("/app/rle.json"))
h, w = rle["size"]
counts = rle["counts"]
flat = [0] * (h * w)
pos = 0
bit = 0
for c in counts:
    for _ in range(c):
        flat[pos] = bit
        pos += 1
    bit = 1 - bit

mask = [flat[r*w:(r+1)*w] for r in range(h)]
out = {"mask": mask, "area": sum(flat)}
json.dump(out, open("/app/mask.json", "w"))
EOF

python3 /app/decode.py