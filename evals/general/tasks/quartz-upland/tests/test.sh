#!/bin/bash
# Quartz Upland verifier. Runs after the agent finishes; /tests is mounted
# read-only. Writes the numeric reward to /logs/verifier/reward.txt.
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier

reward=0
if python3 /tests/driver.py; then
    reward=1
fi

echo "$reward" > /logs/verifier/reward.txt
echo "quartz-upland verifier reward=$reward" >&2
exit 0