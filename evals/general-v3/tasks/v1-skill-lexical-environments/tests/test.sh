#!/bin/bash
mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0
if [ -f "$APP/answer.json" ]; then
  if python3 - "$APP/answer.json" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
sys.exit(0 if d == {"output": [11, 16, 19]} else 1)
PY
  then reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt