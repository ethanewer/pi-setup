#!/bin/bash
# Verifier for cinder-fleet (executes-deliverable). check.py runs
# /app/extract.py on the shipped workspace and on every hidden dump, verifies
# /app/secret.txt normalization against the expected secret, /app/pin.txt, and
# the /app/records.json record table, and compares the deliverables with a
# fresh run. Writes the reward to /logs/verifier/reward.txt (1 all pass,
# 0 otherwise).
set -u
mkdir -p /logs/verifier
python3 /tests/check.py > /tmp/verify_out.log 2>&1
cat /tmp/verify_out.log
reward="$(cat /logs/verifier/reward.txt 2>/dev/null || echo 0)"
echo "$reward" > /logs/verifier/reward.txt
echo "reward=$reward" >&2
exit 0
