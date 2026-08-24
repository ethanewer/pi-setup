#!/bin/bash
set -euo pipefail
python3 - <<'EOF' > /app/event.txt
import csv
rows = [r for r in csv.DictReader(open('/app/motion.csv'))]
x = [float(r['x']) for r in rows]
ts = [float(r['t']) for r in rows]
prev = None
for i in range(len(x) - 1):
    v = x[i+1] - x[i]
    if prev is not None and prev > 0 and v < 0:
        print("%g" % ts[i])
        break
    if v != 0:
        prev = v
EOF
echo "wrote event time"