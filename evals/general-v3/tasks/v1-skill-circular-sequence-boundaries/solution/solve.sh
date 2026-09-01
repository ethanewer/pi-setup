#!/bin/bash
set -euo pipefail

cat > /app/wrap.py <<'EOF'
import json

d = json.load(open("/app/seq.json"))
seq = d["seq"]
n = len(seq)
out = {"values": [seq[i % n] for i in d["queries"]]}
json.dump(out, open("/app/wrapped.json", "w"))
EOF

python3 /app/wrap.py