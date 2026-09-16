#!/bin/bash
# marline-trough verifier entrypoint: delegates to /tests/verify.py and maps
# its exit code to the binary reward. /tests/verify.py implements the three
# gates (streaming static check, independent output correctness, peak-RSS
# ceiling from /proc), printing a readable failure list to stdout.
#
# Guarantee a reward on every exit path. Without this a verifier that raises
# while inspecting the agent's deliverable writes nothing at all, which
# yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -uo pipefail
mkdir -p /logs/verifier

if python3 /tests/verify.py > /tmp/marline-verify.log 2>&1; then
  echo "1" > /logs/verifier/reward.txt
else
  cat /tmp/marline-verify.log
  echo "0" > /logs/verifier/reward.txt
fi
exit 0