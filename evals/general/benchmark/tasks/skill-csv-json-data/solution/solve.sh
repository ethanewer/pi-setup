#!/bin/bash
set -euo pipefail
cat > /app/convert.py <<'PY'
import csv, json

rows = []
with open('/app/data.csv', newline='') as f:
    r = csv.DictReader(f)
    for d in r:
        rows.append({"id": d['id'], "name": d['name'],
                     "role": d['role'], "years": int(d['years'])})
with open('/app/output.json', 'w') as f:
    json.dump(rows, f)
PY
python3 /app/convert.py