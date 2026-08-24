#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/answer.json ]; then
  if python3 - <<'PYEOF'
import json
got = json.load(open('/app/answer.json'))
route = "".join(ch for ch in str(got.get('route', '')).upper() if ch.isalpha())
assert route == "ACBD", route
assert int(got.get('total_distance', -1)) == 13, got.get('total_distance')
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt