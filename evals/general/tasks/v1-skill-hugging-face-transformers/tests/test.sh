#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/toks.json ]; then
  if python3 - <<'PYEOF'
import json
got = json.load(open('/app/toks.json'))
exp = [2, 5, 7, 3]
assert got == exp, (got, exp)
PYEOF
then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt