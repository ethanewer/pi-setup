#!/bin/bash
# Verifier driver for elm-terrace: run the full check suite and write reward.
# Expected rewards: 1 after a clean/production run, 0 otherwise.
set -u

mkdir -p /logs/verifier
cp /tests/verify.py /tmp/verify.py

if python3 /tmp/verify.py; then
    reward=1
    echo "VERIFIER REWARD 1: all checks passed"
else
    reward=0
    echo "VERIFIER REWARD 0: one or more checks failed"
fi

echo "$reward" > /logs/verifier/reward.txt
exit 0