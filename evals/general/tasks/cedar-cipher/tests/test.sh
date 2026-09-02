#!/usr/bin/env bash
# Cedar-cipher verifier entrypoint. Delegates all checking to /tests/verify.py,
# then writes the numeric reward to /logs/verifier/reward.txt.
set -uo pipefail
mkdir -p /logs/verifier

python3 /tests/verify.py
rc=$?

if [ "$rc" -eq 0 ]; then
  reward=1
else
  reward=0
fi
echo "$reward" > /logs/verifier/reward.txt
echo "REWARD=$reward"
exit 0