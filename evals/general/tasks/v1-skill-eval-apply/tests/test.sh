#!/bin/bash
mkdir -p /logs/verifier
reward=0
if python3 - <<'PYEOF'
import json
d = json.load(open('/app/result.json'))
assert d.get('value') == 49, d
PYEOF
then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt