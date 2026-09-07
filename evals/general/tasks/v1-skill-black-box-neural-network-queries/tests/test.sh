#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

reward=0
if [ -f /app/classifications.txt ]; then
  if python3 - <<'PYEOF'
import sys
sys.path.insert(0, '/app')
from nn import predict
points = []
for ln in open('/app/test_points.txt'):
    ln = ln.strip()
    if ln:
        x, y = ln.split()
        points.append((int(x), int(y)))
exp = [1 if predict(x, y) else 0 for (x, y) in points]
got = [int(x) for x in open('/app/classifications.txt').read().split()]
assert got == exp, (got, exp)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt