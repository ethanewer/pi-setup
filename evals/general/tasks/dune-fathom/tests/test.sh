#!/usr/bin/env bash
# Verifier for dune-fathom (executes-deliverable).
# Delegates all checking to /tests/check.py (a helper under tests/), which boots
# /app/server.py itself, exercises it on hidden route parameters, and validates
# the DB/CSV and byte-fetched deliverables. Reward = 1 iff every check passes.
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
