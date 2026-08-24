#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/answer.txt ] && [ -f /app/solve.py ]; then
  if python3 - <<'PYEOF'
import sys
h = open('/app/input/hex.txt').read().strip()
expected = int(h, 16)
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