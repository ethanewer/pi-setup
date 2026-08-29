#!/bin/bash
# juniper-upland verifier. Runs the independent Python verifier which executes
# /app/schedule.py on the visible fixture and every hidden scenario, validates
# the produced ICS structurally and against the recomputed earliest slot,
# confirms the shipped availability inputs are untouched, re-replays the roster
# producer and byte-compares the per-person snapshots, and checks summary.txt.
# Ends by writing the numeric reward.
set -u

mkdir -p /logs/verifier
reward=0
if python3 /tests/verify.py; then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt
exit 0