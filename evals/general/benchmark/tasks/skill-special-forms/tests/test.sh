#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/answer.txt ]; then
  if python3 - <<'PYEOF'
import sys
got = open('/app/answer.txt').read().strip()
# f(5)=5! = 120
if got != '120':
    sys.exit('expected 120, got %r' % got)
sys.exit(0)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt