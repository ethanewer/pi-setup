#!/bin/bash
set -euo pipefail

cat > /app/analyze.py <<'EOF'
import csv
import json

with open("/app/reviews.tsv") as f:
    rows = list(csv.DictReader(f, delimiter="\t"))

from collections import defaultdict
sums = defaultdict(int)
counts = defaultdict(int)
total = 0
total_sum = 0

for r in rows:
    biz = r["business_id"]
    rat = int(r["rating"])
    sums[biz] += rat
    counts[biz] += 1
    total += 1
    total_sum += rat

per = {b: round(sums[b] / counts[b], 2) for b in sums}

out = {
    "per_business": per,
    "total_reviews": total,
    "overall_average": round(total_sum / total, 2),
}
with open("/app/review_summary.json", "w") as f:
    json.dump(out, f)
EOF

python3 /app/analyze.py