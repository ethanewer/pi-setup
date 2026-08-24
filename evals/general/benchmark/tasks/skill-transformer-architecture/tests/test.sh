#!/bin/bash
mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0
if [ -f "$APP/attention.json" ]; then
  if python3 - "$APP/attention.json" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
if not isinstance(d, list) or len(d) != 3:
    sys.exit(1)
ok = True
for row in d:
    if not isinstance(row, list) or len(row) != 3:
        ok = False
    for x in row:
        if not isinstance(x, (int, float)):
            ok = False
sys.exit(0 if ok else 1)
PY
  then reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt