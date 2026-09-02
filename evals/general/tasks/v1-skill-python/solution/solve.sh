#!/bin/bash
set -euo pipefail

cat > /app/analyze.py <<'PYEOF'
import csv
import json

rows = list(csv.DictReader(open('/app/sales.csv', newline='')))
amounts = [int(r['amount']) for r in rows]
count = len(amounts)
total = sum(amounts)
avg = total / count

with open('/app/stats.json', 'w') as f:
    json.dump({'count': count, 'total': total, 'avg': avg}, f)
PYEOF

python3 /app/analyze.py
echo "wrote /app/stats.json"