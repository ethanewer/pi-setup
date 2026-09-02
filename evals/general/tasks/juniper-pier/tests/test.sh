#!/usr/bin/env bash
# Verifier for juniper-pier (executes-deliverable). Delegates scoring to
# verify.py, which runs the deliverable's posterior/penalty phases on the visible
# data, on hidden datasets, and cross-checks the hyperparameter map, posterior
# accuracy/determinism, and penalty corroboration. Writes reward to
# /logs/verifier/reward.txt.
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