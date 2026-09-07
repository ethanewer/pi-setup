#!/usr/bin/env bash
# Gale Pier verifier entrypoint. Runs verify.py which executes every deliverable
# (including on hidden inputs) and writes a numeric reward to
# /logs/verifier/reward.txt.
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u
mkdir -p /logs/verifier
cd /app

python3 /tests/verify.py
rc=$?

if [ -s /logs/verifier/reward.txt ]; then
  reward=$(cat /logs/verifier/reward.txt)
else
  reward=0
fi
if [ "$rc" != "0" ]; then
  reward=0
  echo "0" > /logs/verifier/reward.txt
fi

echo "$reward" > /logs/verifier/reward.txt
echo "reward=$reward" >&2
exit 0