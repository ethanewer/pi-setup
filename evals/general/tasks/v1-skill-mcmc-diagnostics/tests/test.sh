#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
reward=0
if [ -f /app/answer.json ]; then
  if python3 - <<'PYEOF'
import json, math
exp = math.sqrt(21.0 / 20.0)
got = json.load(open('/app/answer.json'))
v = float(got.get('rhat', -1))
assert abs(v - exp) <= 0.01, (v, exp)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt