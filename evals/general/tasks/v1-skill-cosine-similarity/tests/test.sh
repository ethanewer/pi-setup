#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/sim.txt ]; then
  if python3 - <<'PYEOF'
import json, math
a = json.load(open('/app/a.json'))
b = json.load(open('/app/b.json'))
na = math.sqrt(sum(x*x for x in a))
nb = math.sqrt(sum(x*x for x in b))
if na == 0 or nb == 0:
    c = 0.0
else:
    c = sum(x*y for x, y in zip(a, b)) / (na * nb)
exp = "{:.6f}".format(c)
got = open('/app/sim.txt').read().strip()
assert got == exp, (got, exp)
PYEOF
then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt