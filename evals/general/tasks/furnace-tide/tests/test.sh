#!/bin/bash
# Verifier for furnace-tide (executes-deliverable). Delegates all checking to
# the helper /tests/check.py, which re-executes the deliverable scorer on the
# visible input, hidden inputs, edge cases, and a 1.2M-patch stress set under a
# hard peak-RSS cap and wall-clock deadline. Reward = 1 iff every check passes.
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

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
