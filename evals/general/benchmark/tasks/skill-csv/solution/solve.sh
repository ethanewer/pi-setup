#!/bin/bash
set -euo pipefail

cat > /app/process_csv.py <<'PYEOF'
import csv

codes = {'sales': '01', 'engineering': '02', 'support': '03'}

with open('/app/people.csv', newline='') as f:
    reader = csv.reader(f)
    header = next(reader)
    data = list(reader)

out_header = header + ['dept_code']

with open('/app/report.csv', 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(out_header)
    for row in data:
        dept = row[2]
        code = codes.get(dept, '00')
        w.writerow(row + [code])
PYEOF

python3 /app/process_csv.py