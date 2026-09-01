#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/bitwise.json ]; then
  if python3 - <<'PYEOF'
import json
nums=[int(x) for x in open('/app/numbers.txt').read().split()]
sp=sum(bin(n).count('1') for n in nums)
aa=~0
xo=0
for n in nums:
    aa &= n; xo ^= n
exp={'sum_popcounts': sp, 'and_all': aa, 'xor_all': xo}
got=json.load(open('/app/bitwise.json'))
if got != exp:
    raise SystemExit((got, exp))
print("PASS"); raise SystemExit(0)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt