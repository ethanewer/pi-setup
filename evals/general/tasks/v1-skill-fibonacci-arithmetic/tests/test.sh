#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
reward=0
if [ -f /app/fib.json ]; then
  if python3 - <<'PYEOF'
import json
from functools import lru_cache
MOD = 1_000_000_007
n = int(open('/app/n.txt').read().strip())
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
exp = {'n': n, 'F_n': fib(n)[0], 'S_n': (fib(n + 2)[0] - 1) % MOD}
got = json.load(open('/app/fib.json'))
if got.get('n') != exp['n']:
    raise SystemExit('n mismatch')
if got.get('F_n') != exp['F_n']:
    raise SystemExit('F_n mismatch')
if got.get('S_n') != exp['S_n']:
    raise SystemExit('S_n mismatch')
modv = got.get('MOD', got.get('mod'))
if modv != MOD:
    raise SystemExit('mod mismatch')
print("PASS"); raise SystemExit(0)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt