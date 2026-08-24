#!/bin/bash
mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0
if [ -f "$APP/parsed.json" ]; then
  if python3 - "$APP/parsed.json" <<'PYEOF'
import json, sys
exp = {"mode": "fast", "count": 7, "label": "two words", "file": "/tmp/file1.txt"}
try:
    got = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
sys.exit(0 if got == exp else 1)
PYEOF
  then reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt