#!/bin/bash
mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0
if [ -f "$APP/test_inputs.txt" ] && [ -f "$APP/predictions.txt" ]; then
  if python3 - "$APP" <<'PY'
import sys
base = sys.argv[1]
ins = [int(x) for x in open(base + '/test_inputs.txt').read().split() if x.strip()]
exp = [str(n * n + 1) for n in ins]
got = [l.strip() for l in open(base + '/predictions.txt') if l.strip() != '']
sys.exit(0 if got == exp else 1)
PY
  then reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt