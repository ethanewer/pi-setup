#!/bin/bash
set -euo pipefail
python3 - <<'EOF'
import json
items = json.load(open('/app/items.json'))
factors = {"kg": 1.0, "g": 0.001, "oz": 0.028349523125, "lb": 0.45359237}
out = [{"name": it["name"], "weight_kg": round(it["weight"] * factors[it["unit"]], 6)} for it in items]
with open('/app/normalized.json','w') as f:
    json.dump(out, f, indent=2)
print("wrote", len(out), "items")
EOF