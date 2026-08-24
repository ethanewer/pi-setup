#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/answer.txt ]; then
  if python3 - <<'PYEOF'
import sys
got = open('/app/answer.txt').read().strip()
# sum of i*i for i in 1..5 = 1+4+9+16+25 = 55
if got != '55':
    sys.exit('expected 55, got %r' % got)
sys.exit(0)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt