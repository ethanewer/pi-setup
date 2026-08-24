#!/bin/bash
set -euo pipefail
mkdir -p /app/mypkg
cat > /app/mypkg/__init__.py <<'PY'
def classify(n):
    if n < 0:
        return "negative"
    if n == 0:
        return "zero"
    return "positive"
PY
cat > /app/driver.py <<'PY'
import sys
sys.path.insert(0, '/app')
from mypkg import classify
with open('/app/input.txt') as f:
    nums=[int(l.strip()) for l in f if l.strip()]
with open('/app/results.txt','w') as f:
    for n in nums:
        f.write(classify(n)+'\n')
PY
python3 /app/driver.py
echo "wrote results.txt"
