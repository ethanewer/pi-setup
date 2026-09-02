#!/usr/bin/env bash
# iris-anchor verifier. Runs every deliverable and its hidden-case re-runs.
set -uo pipefail
REWARD=0
python3 /tests/verify.py
RC=$?
if [ "$RC" -eq 0 ]; then
  REWARD=1
fi
echo "$REWARD" > /logs/verifier/reward.txt
echo "verify rc=$RC reward=$REWARD"
exit 0