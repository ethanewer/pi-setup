#!/bin/bash
set -euo pipefail
cat > /app/clean.py <<'PY'
import csv, re

with open('/app/records.csv', newline='') as fin, open('/app/cleaned.csv', 'w', newline='') as fout:
    r = csv.reader(fin)
    w = csv.writer(fout)
    header = next(r)
    w.writerow(header)
    for row in r:
        row = [c.strip() for c in row]
        row[1] = row[1].lower()
        row[2] = re.sub(r'\s+', ' ', row[2]).lower()
        w.writerow(row)
PY
python3 /app/clean.py