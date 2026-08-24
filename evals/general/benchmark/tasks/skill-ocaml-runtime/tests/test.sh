#!/bin/bash
mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0
if [ -f "$APP/input.txt" ] && [ -f "$APP/answer.txt" ]; then
  if python3 - "$APP" <<'PYEOF'
import sys
base = sys.argv[1]
nums = [int(x) for x in open(base + '/input.txt') if x.strip()]
exp = str(sum(nums)) + '\n'
got = open(base + '/answer.txt').read()
sys.exit(0 if got == exp else 1)
PYEOF
  then reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt