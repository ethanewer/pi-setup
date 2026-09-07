#!/bin/bash
# echo-latch verifier. Executes the /app/reclaim_fd.py deliverable against the
# live visible keeper and against fresh hidden keeper processes with different
# payloads, pidfile locations, and decoys. Writes /logs/verifier/reward.txt.
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u

mkdir -p /logs/verifier
reward=0
if python3 /tests/verify.py; then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
