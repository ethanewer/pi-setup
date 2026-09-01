#!/usr/bin/env bash
# Verifier for dune-fathom (executes-deliverable).
# Delegates all checking to /tests/check.py (a helper under tests/), which boots
# /app/server.py itself, exercises it on hidden route parameters, and validates
# the DB/CSV and byte-fetched deliverables. Reward = 1 iff every check passes.
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
