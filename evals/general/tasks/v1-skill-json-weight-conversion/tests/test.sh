#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
reward=0
if [ -f /app/normalized.json ]; then
  if python3 - <<'PYEOF'
import json
items = json.load(open('/app/items.json'))
factors = {"kg": 1.0, "g": 0.001, "oz": 0.028349523125, "lb": 0.45359237}
exp = [{"name": it["name"], "weight_kg": round(it["weight"] * factors[it["unit"]], 6)} for it in items]
got = json.load(open('/app/normalized.json'))
assert got == exp, (got, exp)
PYEOF
then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt