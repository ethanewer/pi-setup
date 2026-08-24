#!/bin/bash
set -euo pipefail
cat > /app/solve.py <<'PY'
with open('/app/input/hex.txt', 'r') as fh:
    h = fh.read().strip()
value = int(h, 16)
with open('/app/answer.txt', 'w') as out:
    out.write(str(value))
PY
python3 /app/solve.py
echo "wrote /app/answer.txt"