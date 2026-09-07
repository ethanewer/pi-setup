#!/usr/bin/env bash
# Verifier for juniper-notch (executes-deliverable).
# Delegates all scenario checking (including the hidden cases under
# /tests/hidden) to /tests/check.py, which boots a fresh unauthenticated MQ
# bus and survey gate, executes the /app deliverables on hidden inputs, and
# validates the resulting receipts and survey line. Reward = 1 iff all pass.
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u
mkdir -p /logs/verifier

# The three deliverables must exist on /app.
test -f /app/q.py        || { echo "0" > /logs/verifier/reward.txt; exit 0; }
test -f /app/job.json    || { echo "0" > /logs/verifier/reward.txt; exit 0; }
test -f /app/roundtrip.out || { echo "0" > /logs/verifier/reward.txt; exit 0; }

python3 /tests/check.py
rc=$?

if [ "$rc" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0