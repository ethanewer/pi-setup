#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/result.json ]; then
  if python3 - <<'PYEOF'
import json
d = json.load(open('/app/data.json'))
a = int(d['a']); b = int(d['b'])
MASK = 0xFFFFFFFF
exp = {'a': a, 'b': b, 'sum_wrapped': (a + b) & MASK, 'xor': a ^ b}
got = json.load(open('/app/result.json'))
assert got == exp, (got, exp)
PYEOF
then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt