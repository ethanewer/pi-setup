#!/bin/bash
set -euo pipefail

cat > /app/legacy.py <<'PYEOF'
data = open("input.txt").read().strip()
parts = data.split(",")
nums = [int(x) for x in parts]
total = sum(nums)
n = len(nums)
avg = total / n
print("sum=%d count=%d avg=%s" % (total, n, avg))
PYEOF

python3 /app/legacy.py > /app/out.txt
echo "wrote /app/out.txt"