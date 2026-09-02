#!/bin/bash
mkdir -p /logs/verifier
reward=0
if python3 - <<'PYEOF'
import json
n = int(open('/app/n.txt').read().strip())
a, b = 0, 1
for _ in range(n):
    a, b = b, a + b
got = json.load(open('/app/fib.json'))
assert got.get('n') == n, got
assert got.get('value') == a, (got.get('value'), a)
PYEOF
then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt