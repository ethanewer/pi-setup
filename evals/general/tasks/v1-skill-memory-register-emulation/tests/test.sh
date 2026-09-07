#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
reward=0
if [ -f /app/reg.json ]; then
  if python3 - <<'EOF'
import json, sys
exp = {"R0": 3, "R1": 12, "R2": 12, "R3": 7}
got = json.load(open('/app/reg.json'))
for k, v in exp.items():
    if int(got.get(k, -1)) != v:
        sys.exit("bad %s" % k)
sys.exit(0)
EOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt