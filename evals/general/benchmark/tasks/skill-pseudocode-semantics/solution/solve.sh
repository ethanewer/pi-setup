#!/bin/bash
set -euo pipefail

cat > /app/pseudocode.py <<'PYEOF'
n = 100
total = 0
for i in range(1, n + 1):
    if (i % 3 == 0) or (i % 5 == 0):
        total += i

with open('/app/result.txt', 'w') as f:
    f.write(str(total) + '\n')
PYEOF

python3 /app/pseudocode.py
echo "wrote /app/result.txt"