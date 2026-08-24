#!/bin/bash
set -euo pipefail
cat > /app/solve.py <<'PY'
total = 0
with open('/app/input/data.txt', 'r') as fh:
    for line in fh:
        s = line.strip()
        if s:
            total += int(s)
with open('/app/answer.txt', 'w') as out:
    out.write(str(total))
PY
python3 /app/solve.py
echo "wrote /app/answer.txt"