#!/bin/bash
# Verifier wrapper for halyard-spire. Everything lives in /tests/verifier.py;
# this wrapper guarantees a reward on every exit path and forwards the
# verifier's exit for harbor.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u
mkdir -p /logs/verifier

python3 /tests/verifier.py
rc=$?

if [ -f /logs/verifier/reward.txt ]; then
  exit "$rc"
fi
exit "$rc"