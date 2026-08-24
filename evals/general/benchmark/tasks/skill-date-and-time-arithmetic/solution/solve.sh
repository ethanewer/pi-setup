#!/bin/bash
set -euo pipefail
cat > /app/add_days.py <<'PY'
from datetime import date, timedelta
rows = []
with open('/app/dates.txt') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        d, n = line.split()
        y, m, day = map(int, d.split('-'))
        dt = date(y, m, day) + timedelta(days=int(n))
        rows.append(dt.isoformat())
with open('/app/results_out.txt', 'w') as f:
    f.write('\n'.join(rows) + '\n')
PY
python3 /app/add_days.py
