#!/bin/bash
set -euo pipefail
cat > /app/classify.py <<'PYEOF'
import sys
sys.path.insert(0, '/app')
from nn import predict
pts = []
for ln in open('/app/test_points.txt'):
    ln = ln.strip()
    if ln:
        x, y = ln.split()
        pts.append((int(x), int(y)))
with open('/app/classifications.txt', 'w') as f:
    for (x, y) in pts:
        f.write(('1' if predict(x, y) else '0') + chr(10))
PYEOF
python3 /app/classify.py
