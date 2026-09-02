#!/bin/bash
# Verifier for opal-fathom: executes the deliverable program (/app/eval_policy.py)
# on the visible case and on every hidden case in /tests/hidden, requiring a
# deterministic seeded rollout that matches an independent reference. Writes
# 0/1 to /logs/verifier/reward.txt.
set -uo pipefail

mkdir -p /logs/verifier
REWARD=0

if python3 /tests/verify.py /app/case /tests/hidden >/tmp/opal_fathom_verify.log 2>&1; then
  REWARD=1
else
  sed -n '1,40p' /tmp/opal_fathom_verify.log >&2
fi

echo "$REWARD" > /logs/verifier/reward.txt
echo "REWARD=$REWARD"
exit 0
