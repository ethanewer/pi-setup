#!/usr/bin/env bash
# Verifier for cedar-pier (executes-deliverable). verify.py executes /app/train.py
# on the visible dataset, on every hidden core fold, and in debug mode; loads the
# serialized model (signed constrained coefficient, parameter shape), parses the
# row-wise numeric vector, computes hidden/visible accuracy vs the floor, checks
# that the malformed dataset triggers a clean non-zero exit, and inspects the
# experiment-data directory. It writes the reward to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
cd /app
export PYTHONUNBUFFERED=1

python3 /tests/verify.py
rc=$?
if [ "$rc" != "0" ]; then
  echo "0" > /logs/verifier/reward.txt
fi
reward=$(cat /logs/verifier/reward.txt 2>/dev/null || echo "0")
echo "$reward" > /logs/verifier/reward.txt
echo "reward=$reward" >&2
exit 0