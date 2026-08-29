#!/usr/bin/env bash
# Verifier: run the reference checker and write the numeric reward.
set -uo pipefail
mkdir -p /logs/verifier

python3 /tests/verify.py
rc=$?

if [ "$rc" -eq 0 ]; then
    echo 1 > /logs/verifier/reward.txt
else
    echo 0 > /logs/verifier/reward.txt
fi
exit 0