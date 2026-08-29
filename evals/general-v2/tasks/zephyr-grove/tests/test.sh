#!/bin/bash
# Verifier for zephyr-grove (executes-deliverable).
# Runs the independent check harness tests/verify.py, which re-runs /app/solver.py
# on the visible and every hidden config and checks the literal /app deliverables.
# Ends by writing the numeric reward to /logs/verifier/reward.txt.
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