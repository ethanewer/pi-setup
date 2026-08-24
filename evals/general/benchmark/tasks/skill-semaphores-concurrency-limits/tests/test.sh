#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/result.json ]; then
  if python3 - <<'PYEOF'
import json
res = json.load(open('/app/result.json'))
limit = int(res.get('limit'))
total = int(res.get('total'))
completed = int(res.get('completed'))
peak = int(res.get('peak'))
assert limit == 4, res
assert total == 30, res
assert completed == total, res
assert 1 <= peak <= limit, res
assert peak == limit, res
PYEOF
then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt