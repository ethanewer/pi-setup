#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

reward=0
mkdir -p /logs/verifier
if [ -f /app/sum.txt ]; then
  if [ "$(cat /app/sum.txt)" == "40" ]; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt