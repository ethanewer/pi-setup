#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
reward=0
if [ -f /app/fret_efficiency.json ]; then
  if python3 - <<'EOF'
import json
d = json.load(open('/app/data.json'))
expected = round(1.0 - (d['tau_DA'] / d['tau_D']), 4)
out = json.load(open('/app/fret_efficiency.json'))
if out["E"] != expected:
    raise SystemExit((out, expected))
print("PASS"); raise SystemExit(0)
EOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt