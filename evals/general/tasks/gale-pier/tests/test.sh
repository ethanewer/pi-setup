#!/usr/bin/env bash
# Gale Pier verifier entrypoint. Runs verify.py which executes every deliverable
# (including on hidden inputs) and writes a numeric reward to
# /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
cd /app

python3 /tests/verify.py
rc=$?

if [ -s /logs/verifier/reward.txt ]; then
  reward=$(cat /logs/verifier/reward.txt)
else
  reward=0
fi
if [ "$rc" != "0" ]; then
  reward=0
  echo "0" > /logs/verifier/reward.txt
fi

echo "$reward" > /logs/verifier/reward.txt
echo "reward=$reward" >&2
exit 0