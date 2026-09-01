#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/solve.py ] && [ -f /app/tasklib.py ]; then
  rm -f /app/cancellation.json
  if python3 /app/solve.py 2>/dev/null; then
    if python3 - <<'EOF'
import json, sys
try:
    d=json.load(open('/app/cancellation.json'))
except Exception:
    sys.exit('no json')
if d.get('t1_cancelled') is True and d.get('t2_cancelled') is True:
    sys.exit(0)
sys.exit('not both cancelled')
EOF
    then
      reward=1
    fi
  fi
fi
echo "$reward" > /logs/verifier/reward.txt