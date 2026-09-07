#!/bin/bash
# Verifier for zephyr-grove (executes-deliverable).
# Runs the independent check harness tests/verify.py, which re-runs /app/solver.py
# on the visible and every hidden config and checks the literal /app deliverables.
# Ends by writing the numeric reward to /logs/verifier/reward.txt.
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u
mkdir -p /logs/verifier

python3 /tests/verify.py
rc=$?

if [ "$rc" -eq 0 ]; then
    reward=1
else
    reward=0
fi
echo "$reward" > /logs/verifier/reward.txt
echo "reward=$reward (verifier_exit=$rc)"
exit 0