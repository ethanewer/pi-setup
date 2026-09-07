#!/bin/bash
# Verifier driver for elm-terrace: run the full check suite and write reward.
# Expected rewards: 1 after a clean/production run, 0 otherwise.
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

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