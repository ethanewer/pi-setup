#!/bin/bash
# Verifier for furnace-tide (executes-deliverable). Delegates all checking to
# the helper /tests/check.py, which re-executes the deliverable scorer on the
# visible input, hidden inputs, edge cases, and a 1.2M-patch stress set under a
# hard peak-RSS cap and wall-clock deadline. Reward = 1 iff every check passes.
set -u
mkdir -p /logs/verifier

python3 /tests/check.py
rc=$?

if [ "$rc" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
