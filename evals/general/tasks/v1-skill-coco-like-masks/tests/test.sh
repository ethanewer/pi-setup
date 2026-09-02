#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/mask.json ]; then
  if python3 - <<'PYEOF'
import json
rle = json.load(open('/app/rle.json'))
h, w = rle['size']
counts = rle['counts']
flat = [0]*(h*w)
pos = 0; bit = 0
for c in counts:
    for _ in range(c):
        flat[pos] = bit; pos += 1
    bit = 1 - bit
exp = {'mask': [flat[r*w:(r+1)*w] for r in range(h)], 'area': sum(flat)}
got = json.load(open('/app/mask.json'))
assert got == exp, (got, exp)
PYEOF
then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt