#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
reward=0
if [ -f /app/result.json ]; then
  if python3 - <<'PYEOF'
import json, sys
exp = [45, 54, 66]
got = json.load(open('/app/result.json'))
assert isinstance(got, list) and len(got) == len(exp) and [int(x) for x in got] == exp, got
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt