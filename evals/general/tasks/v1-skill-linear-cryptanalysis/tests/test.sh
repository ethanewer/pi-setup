#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/answer.json ]; then
  if python3 - <<'PYEOF'
import json
sbox = [6, 2, 5, 0, 3, 1, 7, 4]
a, b = 5, 7
exp = sum(1 for i in range(8) if (bin(i & a).count('1') % 2) == (bin(sbox[i] & b).count('1') % 2))
got = json.load(open('/app/answer.json'))
assert int(got.get("count", -1)) == exp, (got, exp)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt