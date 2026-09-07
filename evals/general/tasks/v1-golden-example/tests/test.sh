#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

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