#!/bin/bash
set -euo pipefail
cat > /app/bitwise.py <<'PYEOF'
def popcount(x):
    c = 0
    while x:
        x &= x - 1
        c += 1
    return c
nums = [int(x) for x in open('/app/numbers.txt').read().split()]
sp = sum(popcount(n) for n in nums)
and_all = 0xffffffffffffffff
xor_all = 0
for n in nums:
    and_all &= n
    xor_all ^= n
import json
json.dump({'sum_popcounts': sp, 'and_all': and_all, 'xor_all': xor_all}, open('/app/bitwise.json', 'w'))
PYEOF
python3 /app/bitwise.py
