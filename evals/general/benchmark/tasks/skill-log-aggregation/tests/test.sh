#!/bin/bash
mkdir -p /logs/verifier
reward=0
if python3 - <<'PYEOF'
import json
from collections import Counter
c = Counter()
for line in open('/app/logs/app1.log').read().splitlines() + open('/app/logs/app2.log').read().splitlines() + open('/app/logs/app3.log').read().splitlines():
    line = line.strip()
    if line:
        c[line.split()[1]] += 1
expected = {k: c.get(k, 0) for k in ['INFO', 'WARN', 'ERROR']}
got = json.load(open('/app/summary.json'))
assert got == expected, (got, expected)
PYEOF
then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt