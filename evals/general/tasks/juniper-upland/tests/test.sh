#!/bin/bash
# juniper-upland verifier. Runs the independent Python verifier which executes
# /app/schedule.py on the visible fixture and every hidden scenario, validates
# the produced ICS structurally and against the recomputed earliest slot,
# confirms the shipped availability inputs are untouched, re-replays the roster
# producer and byte-compares the per-person snapshots, and checks summary.txt.
# Ends by writing the numeric reward.
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