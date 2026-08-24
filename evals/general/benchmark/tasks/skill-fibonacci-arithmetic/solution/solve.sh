#!/bin/bash
set -euo pipefail

cat > /app/fibmod.py <<'PYEOF'
import json
from functools import lru_cache

MOD = 1_000_000_007
n = int(open('/app/n.txt').read().strip())

# fast doubling: fib(k) returns (F(k) % MOD, F(k+1) % MOD)
@lru_cache(maxsize=None)
def fib(k):
    if k == 0:
        return (0, 1)
    a, b = fib(k >> 1)
    c = (a * ((2 * b - a) % MOD)) % MOD
    d = (a * a + b * b) % MOD
    if k & 1:
        return (d, (c + d) % MOD)
    return (c, d)

Fn = fib(n)[0]
Sn = (fib(n + 2)[0] - 1) % MOD

with open('/app/fib.json', 'w') as f:
    json.dump({'n': n, 'MOD': MOD, 'F_n': Fn, 'S_n': Sn}, f)
PYEOF

python3 /app/fibmod.py