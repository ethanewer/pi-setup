#!/bin/bash
mkdir -p /logs/verifier

reward=0
if [ -f /app/summary.json ]; then
  if python3 - <<'EOF'
import json, sys
with open("/app/summary.json") as f:
    s = json.load(f)
assert s["rows"] == 4, s
assert abs(s["mean_score"] - 25.0) < 1e-9, s
EOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt