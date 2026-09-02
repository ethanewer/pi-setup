#!/bin/bash
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