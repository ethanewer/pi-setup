#!/bin/bash
mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0
if [ -f "$APP/report.txt" ] && [ -f "$APP/data.csv" ]; then
  if python3 - "$APP" <<'PYEOF'
import sys
base = sys.argv[1]
report = open(base + '/report.txt').read().strip()
if report != '1000000':
    sys.exit(1)
lines = open(base + '/data.csv').read().splitlines()
if len(lines) != 1000001:
    sys.exit(1)
if lines[0] != 'id,code':
    sys.exit(1)
def code(i):
    return chr(65 + (i // 26) % 26) + chr(65 + i % 26)
if lines[1] != code(1) + '-1':
    sys.exit(1)
if lines[-1] != code(1000000) + '-1000000':
    sys.exit(1)
sys.exit(0)
PYEOF
  then reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt