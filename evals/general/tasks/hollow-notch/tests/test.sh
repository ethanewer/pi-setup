#!/usr/bin/env bash
# hollow-notch verifier (executes-deliverable). Runs as root after the agent
# finishes; /app/setup.sh and /app/status.json are the deliverables.
set -u
mkdir -p /logs/verifier

if python3 /tests/check.py; then
    reward=1
else
    reward=0
fi

echo "$reward" > /logs/verifier/reward.txt
echo "reward=${reward}"
exit 0