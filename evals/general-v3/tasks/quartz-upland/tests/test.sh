#!/bin/bash
# Quartz Upland verifier. Runs after the agent finishes; /tests is mounted
# read-only. Writes the numeric reward to /logs/verifier/reward.txt.
mkdir -p /logs/verifier

reward=0
if python3 /tests/driver.py; then
    reward=1
fi

echo "$reward" > /logs/verifier/reward.txt
echo "quartz-upland verifier reward=$reward" >&2
exit 0