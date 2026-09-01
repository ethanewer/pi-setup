#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/answer.json ]; then
  if python3 - <<'PYEOF'
import json, math
exp = math.sqrt(21.0 / 20.0)
got = json.load(open('/app/answer.json'))
v = float(got.get('rhat', -1))
assert abs(v - exp) <= 0.01, (v, exp)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt