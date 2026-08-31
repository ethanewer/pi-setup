#!/usr/bin/env bash
# Verifier for basalt-maze (executes-deliverable).
# Delegates to /tests/check.py, which starts fresh navd daemons (default grid
# and every hidden grid under /tests/hidden), executes the deliverable
# /app/dispatch.py against each, validates the resulting dispatch JSONs
# (legal walk, final position, recomputed arrival token), validates the
# /app/route.json deliverable, and checks the unreachable-goal behaviour.
# Reward = 1 iff all checks pass.
set -u
mkdir -p /logs/verifier

test -f /app/dispatch.py || { echo "0" > /logs/verifier/reward.txt; exit 0; }
test -f /app/route.json || { echo "0" > /logs/verifier/reward.txt; exit 0; }

python3 /tests/check.py
rc=$?

if [ "$rc" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
