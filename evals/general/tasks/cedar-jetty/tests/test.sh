#!/usr/bin/env bash
# cedar-jetty verifier entrypoint. Runs every deliverable against hidden cases.
set -uo pipefail
mkdir -p /logs/verifier

# verifier.py (mounted read-only at /tests at grading time) imports /app/kernels,
# checks /app/out.npy, re-runs each kernel on /tests/hidden and writes the reward.
python3 /tests/verifier.py
rc=$?

# The verifier always writes /logs/verifier/reward.txt; fall back to 0 if missing.
if [ ! -s /logs/verifier/reward.txt ]; then
    echo "0" > /logs/verifier/reward.txt
fi

echo "verifier exited rc=$rc reward=$(cat /logs/verifier/reward.txt)"
exit 0