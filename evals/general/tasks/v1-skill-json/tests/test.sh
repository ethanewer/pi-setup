#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
reward=0
exp=$(python3 -c "import json; print(json.load(open('/app/config.json'))['server']['port'])" 2>/dev/null)
if [ -n "$exp" ] && [ -f /app/port_output.txt ]; then
  got=$(python3 -c "print(open('/app/port_output.txt').read().strip())" 2>/dev/null)
  if [ "$got" = "$exp" ]; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt