#!/usr/bin/env bash
# Verifier for quill-fathom (executes-deliverable). Delegates to /tests/check.py,
# which re-executes /app/adapt.py on the visible fold and on hidden press folds,
# and validates /app/adapted_press.pt. Reward = 1 iff every check passes.
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
