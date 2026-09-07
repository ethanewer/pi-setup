#!/usr/bin/env bash
# iris-anchor verifier. Runs every deliverable and its hidden-case re-runs.
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

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