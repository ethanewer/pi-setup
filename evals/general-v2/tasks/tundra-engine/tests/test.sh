#!/usr/bin/env bash
# tundra-engine verifier (executes-deliverable).
# Runs the agent's /app/solve.py on the visible spec and every hidden fixture
# and rewards 1 only when every independent check passes.
set -u

mkdir -p /logs/verifier
reward=0

if [ ! -f /app/solve.py ] || [ ! -f /app/answer.json ]; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

if python3 /tests/check.py; then
    reward=1
else
    reward=0
fi

echo "${reward}" > /logs/verifier/reward.txt
echo "reward=${reward}"
exit 0