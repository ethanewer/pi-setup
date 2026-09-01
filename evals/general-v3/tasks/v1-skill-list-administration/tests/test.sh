#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/result.json ]; then
  if python3 - <<'PYEOF'
import json, sys
exp = [45, 54, 66]
got = json.load(open('/app/result.json'))
assert isinstance(got, list) and len(got) == len(exp) and [int(x) for x in got] == exp, got
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt