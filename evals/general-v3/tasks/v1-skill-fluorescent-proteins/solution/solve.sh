#!/bin/bash
set -euo pipefail

cat > /app/find.py <<'EOF'
import csv, json

target = int(open('/app/query.txt').read().strip())
with open('/app/proteins.csv') as f:
    rows = list(csv.DictReader(f))

best_name = None
best_dist = None
for r in rows:
    pe = int(r['peak_emission'])
    d = abs(pe - target)
    if best_dist is None or d < best_dist:
        best_dist = d
        best_name = r['name']

pe = int(next(r['peak_emission'] for r in rows if r['name'] == best_name))
with open('/app/result.json', 'w') as f:
    json.dump({"name": best_name, "peak_emission": pe}, f)
EOF
python3 /app/find.py