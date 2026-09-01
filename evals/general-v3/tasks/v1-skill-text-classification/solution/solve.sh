#!/bin/bash
set -euo pipefail

cat > /app/classify.py <<'PY'
import json

positive = set()
negative = set()
with open("/app/training.txt") as f:
    for line in f:
        line = line.strip()
        if not line or "\t" not in line:
            continue
        word, label = line.split("\t")
        (positive if label == "pos" else negative).add(word)

with open("/app/test.txt") as f:
    test_lines = [ln.strip() for ln in f if ln.strip()]

preds = []
for line in test_lines:
    tokens = line.split()
    if any(w in positive for w in tokens):
        preds.append("pos")
    elif any(w in negative for w in tokens):
        preds.append("neg")
    else:
        preds.append("pos")

with open("/app/predictions.json", "w") as f:
    json.dump(preds, f)
PY

python3 /app/classify.py