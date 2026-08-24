#!/bin/bash
mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0
if [ -f "$APP/result.txt" ]; then
  if python3 - "$APP/result.txt" <<'PY'
import sys
try:
    lines = [l.strip() for l in open(sys.argv[1]) if l.strip()]
    if not lines:
        sys.exit(1)
    got = int(lines[-1])
except Exception:
    sys.exit(1)
expected = sum(i for i in range(1, 101) if i % 3 == 0 or i % 5 == 0)
sys.exit(0 if got == expected else 1)
PY
  then reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt