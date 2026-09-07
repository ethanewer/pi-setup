#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
reward=0
if [ -f /app/result.json ]; then
  if python3 - <<'PYEOF'
import json, math

mu, sigma, x = 50.0, 12.0, 44.0
expected = 0.5 * (1.0 + math.erf((x - mu) / (sigma * math.sqrt(2.0))))

with open('/app/result.json') as f:
    data = json.load(f)
got = float(data['p'])
assert abs(got - expected) < 1e-6, (got, expected)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt