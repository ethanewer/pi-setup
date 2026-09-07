#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

reward=0
mkdir -p /logs/verifier
cd /app/repo 2>/dev/null || { echo "$reward" > /logs/verifier/reward.txt; exit 0; }
git checkout -q v2 2>/dev/null
expected=$(cat version.txt 2>/dev/null)
got=$(cat /app/answer.txt 2>/dev/null)
if [ -n "$expected" ] && [ "$got" == "$expected" ]; then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt