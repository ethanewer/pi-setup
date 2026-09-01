#!/bin/bash
set -euo pipefail

cat > /app/check.py <<'PY'
import json

with open('/app/reference.json') as f:
    ref = json.load(f)
with open('/app/actual.json') as f:
    act = json.load(f)
with open('/app/tolerance.json') as f:
    tol = json.load(f)

lines = []
all_ok = True
for key in ['temp', 'pressure', 'level']:
    ok = abs(act[key] - ref[key]) <= tol[key]
    lines.append(f"{key}={'PASS' if ok else 'FAIL'}")
    all_ok = all_ok and ok
lines.append('all=' + ('PASS' if all_ok else 'FAIL'))

with open('/app/result.txt', 'w') as f:
    f.write('\n'.join(lines) + '\n')
PY

python3 /app/check.py