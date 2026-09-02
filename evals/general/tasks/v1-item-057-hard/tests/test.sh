#!/bin/bash
# Verifier for item-057-hard: recompute count/sum from numbers.txt.
mkdir -p /logs/verifier
reward=0

if [ -f /app/numbers.txt ] && [ -f /app/answer.json ]; then
  if python3 - <<'PYEOF'
import sys, json

nums = []
with open('/app/numbers.txt') as fh:
    for line in fh:
        line = line.strip()
        if line:
            nums.append(int(line))

expected = {'count': len(nums), 'sum': sum(nums)}

try:
    got = json.load(open('/app/answer.json'))
except Exception:
    sys.exit(1)

if not isinstance(got, dict):
    sys.exit(1)
if {k: got.get(k) for k in expected} != expected:
    sys.exit(1)
print('item-057 probe verified')
PYEOF
  then
    reward=1
  fi
fi

echo "$reward" > /logs/verifier/reward.txt