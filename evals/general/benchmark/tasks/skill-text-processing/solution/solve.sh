#!/bin/bash
set -euo pipefail

cat > /app/process.py <<'PY'
import json

with open("/app/input.txt") as f:
    text = f.read()

words = text.split()
lines = [ln for ln in text.split("\n") if ln.strip()]

summary = {"words": len(words), "lines": len(lines)}
with open("/app/summary.json", "w") as f:
    json.dump(summary, f)
PY

python3 /app/process.py
echo "wrote /app/summary.json"