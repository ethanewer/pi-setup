#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
reward=0
if [ -f /app/browser_answers.json ]; then
  if python3 - <<'PYEOF'
import json, sys
d = json.load(open('/app/browser_answers.json'))
expected = {
    "q1": "true", "q2": "true", "q3": "DOMContentLoaded", "q4": "true",
    "q5": "true", "q6": "true", "q7": "false", "q8": "false",
}
ok = (set(d) == set(expected)
      and all(str(d[k]).lower() == v.lower() for k, v in expected.items()))
sys.exit(0 if ok else 1)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt
