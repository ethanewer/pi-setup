#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/answer.txt ] && [ -f /app/solve.py ]; then
  if python3 - <<'PYEOF'
import sys
expected = 0
with open('/app/input/data.txt', 'r') as fh:
    for line in fh:
        s = line.strip()
        if s:
            expected += int(s)
got = open('/app/answer.txt').read().strip()
if got != str(expected):
    sys.exit('expected %d, got %r' % (expected, got))
sys.exit(0)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt