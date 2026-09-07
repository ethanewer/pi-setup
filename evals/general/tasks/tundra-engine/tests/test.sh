#!/usr/bin/env bash
# tundra-engine verifier (executes-deliverable).
# Runs the agent's /app/solve.py on the visible spec and every hidden fixture
# and rewards 1 only when every independent check passes.
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

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