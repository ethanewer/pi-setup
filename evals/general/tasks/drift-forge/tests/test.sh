#!/usr/bin/env bash
# Ridgeline drift-forge verifier. Runs as root after the agent finishes.
# Writes 1 to /logs/verifier/reward.txt on success, else 0.
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u

REWARD=0
if python3 /tests/verify.py; then
  REWARD=1
fi

mkdir -p /logs/verifier
printf '%s\n' "$REWARD" > /logs/verifier/reward.txt
exit 0