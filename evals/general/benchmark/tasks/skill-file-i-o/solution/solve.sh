#!/bin/bash
set -euo pipefail

cat > /app/io.py <<'PYEOF'
vals = []
with open('/app/input.txt') as f:
    for line in f:
        s = line.strip()
        if s:
            vals.append(int(s))

total = sum(vals)
count = len(vals)
mean = total / count

with open('/app/output.txt', 'w') as f:
    f.write(f"sum={total}\ncount={count}\nmean={mean}\n")
PYEOF

python3 /app/io.py