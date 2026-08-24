#!/bin/bash
set -euo pipefail
cat > /app/verify.py <<'PY'
import csv
from datetime import date
start = date(2024, 1, 1)
end = date(2024, 12, 31)
valid = []
with open('/app/records.csv', newline='') as f:
    for row in csv.DictReader(f):
        y, m, d = map(int, row['entry_date'].split('-'))
        dt = date(y, m, d)
        if start <= dt <= end:
            valid.append(row['id'])
with open('/app/valid_ids.txt', 'w') as f:
    f.write('\n'.join(valid) + '\n')
PY
python3 /app/verify.py
