#!/bin/bash
set -euo pipefail

cat > /app/summarize.py <<'EOF'
import csv, json

with open("/app/data.csv") as f:
    rows = list(csv.DictReader(f))

scores = [float(r["score"]) for r in rows]
summary = {"rows": len(rows), "mean_score": round(sum(scores) / len(scores), 2)}

with open("/app/summary.json", "w") as f:
    json.dump(summary, f)
EOF

python3 /app/summarize.py
