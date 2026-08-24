#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/verdict.txt ]; then
  if python3 - <<'PYEOF'
import itertools
def F(p, q, r):
    imp = lambda a, b: (not a) or b
    return imp(imp(p, q) and imp(q, r), imp(p, r))
all_true = all(F(p, q, r) for p, q, r in itertools.product([True, False], repeat=3))
exp = 'tautology' if all_true else 'nontheorem'
got = open('/app/verdict.txt').read().strip()
assert got == exp, (got, exp)
PYEOF
then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt