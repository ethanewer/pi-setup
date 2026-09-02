#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/layers.json ] && [ -f /app/depths.csv ] && [ -f /app/assignments.json ]; then
  if python3 - <<'PYEOF'
import json
layers = json.load(open('/app/layers.json'))['layers']
depths = [float(x) for x in open('/app/depths.csv').read().strip().split(',')]
exp = {}
for d in depths:
    for L in layers:
        if L['min'] <= d < L['max']:
            exp[str(int(d))] = L['name']
            break
got = json.load(open('/app/assignments.json'))
assert got == exp, (got, exp)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt