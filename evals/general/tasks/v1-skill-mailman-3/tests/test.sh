#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
reward=0
if [ -f /app/answer.json ]; then
  if python3 - <<'PYEOF'
import json
got = json.load(open('/app/answer.json'))
route = "".join(ch for ch in str(got.get('route', '')).upper() if ch.isalpha())
assert route == "ACBD", route
assert int(got.get('total_distance', -1)) == 13, got.get('total_distance')
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt