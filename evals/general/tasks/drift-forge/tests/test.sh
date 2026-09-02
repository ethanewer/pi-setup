#!/usr/bin/env bash
# Ridgeline drift-forge verifier. Runs as root after the agent finishes.
# Writes 1 to /logs/verifier/reward.txt on success, else 0.
set -u

REWARD=0
if python3 /tests/verify.py; then
  REWARD=1
fi

mkdir -p /logs/verifier
printf '%s\n' "$REWARD" > /logs/verifier/reward.txt
exit 0