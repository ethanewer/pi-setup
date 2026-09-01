#!/bin/bash
# Verifier driver for harbor-mantle: run the full check suite and write the
# numeric reward to /logs/verifier/reward.txt. Runs as root after the agent has
# finished; /tests is mounted read-only here.
set -u

mkdir -p /logs/verifier
cp /tests/verify.py /tmp/verify.py

# Force Triton CPU-interpreter mode regardless of how the agent set the env.
export TRITON_INTERPRET=1

if python3 -u /tmp/verify.py; then
    reward=1
    echo "VERIFIER REWARD 1: all checks passed"
else
    reward=0
    echo "VERIFIER REWARD 0: one or more checks failed"
fi

echo "$reward" > /logs/verifier/reward.txt
exit 0