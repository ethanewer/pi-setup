#!/bin/bash
# Verifier for skill-optimization.
# Re-evaluate the same objective at the agent's reported x; require global minimum.
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
reward=0

if [ -f /app/solution.json ]; then
  if python3 - <<'PYEOF'
import json, sys
sys.path.insert(0, '/app')
from objective import objective

got = json.load(open('/app/solution.json'))
x = [float(got['x'][0]), float(got['x'][1])]
f = objective(x)

assert abs(x[0] - 2.5) < 0.01, x
assert abs(x[1] - (-1.25)) < 0.01, x
assert f <= 1e-6, ('not at minimum', x, f)
assert abs(float(got['f']) - objective(x)) < 1e-6, (got['f'], objective(x))
PYEOF
  then
    reward=1
  fi
fi

echo "$reward" > /logs/verifier/reward.txt