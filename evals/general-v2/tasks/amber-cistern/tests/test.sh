#!/usr/bin/env bash
# Verifier for amber-cistern (executes-deliverable).
# Delegates all scenario checking (including the hidden cases under
# /tests/hidden) to /tests/check.py, which boots fresh slotd services on the
# visible and hidden tables, executes the deliverable /app/probe.py on every
# manifest, and validates the summaries. Reward = 1 iff all pass.
set -u
mkdir -p /logs/verifier

test -f /app/probe.py    || { echo "0" > /logs/verifier/reward.txt; exit 0; }
test -f /app/summary.json || { echo "0" > /logs/verifier/reward.txt; exit 0; }

python3 /tests/check.py
rc=$?

if [ "$rc" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
