#!/bin/bash
mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0
if [ -f "$APP/mypkg/__init__.py" ] && [ -f "$APP/input.txt" ] && [ -f "$APP/results.txt" ]; then
  if python3 - "$APP" <<'PYEOF'
import sys
base = sys.argv[1]
def classify(n):
    if n < 0: return "negative"
    if n == 0: return "zero"
    return "positive"
nums = [int(l.strip()) for l in open(base + '/input.txt') if l.strip()]
exp = [classify(n) for n in nums]
got = [l.rstrip('\n') for l in open(base + '/results.txt') if l.rstrip('\n') != '']
sys.exit(0 if got == exp else 1)
PYEOF
  then reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt