#!/usr/bin/env bash
# Verifier for coral-basin (executes-deliverable). Delegates to /tests/check.py,
# which re-executes /app/bag_mean.py on the visible bag, on hidden bags, and on
# a large generated stress bag under a peak-RSS cap and wall-clock deadline.
# Reward = 1 iff every check passes.
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
