#!/usr/bin/env bash
# amber-ledge verifier entrypoint.
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -uo pipefail
mkdir -p /logs/verifier
if python3 /tests/verify.py 2> /tmp/verify.err; then
  echo "1" > /logs/verifier/reward.txt
else
  echo "0" > /logs/verifier/reward.txt
  cat /tmp/verify.err >&2
fi