#!/bin/bash
mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0
if [ -f "$APP/wires.json" ]; then
  if python3 - "$APP/wires.json" <<'PYEOF'
import json, sys
exp = {"A": 1, "B": 0, "C": 0, "D": 1, "E": 1, "F": 1}
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