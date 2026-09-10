#!/bin/bash
# Verifier for bracket-quay (executes-deliverable).
#
# Deliverables:
#   /app/quayside        the repaired quaydoc repository (executed: shipped
#                        pytest suite + hidden checks + example build/check)
#   /app/postmortem.md   postmortem naming the exact introducing commit
#
# The real logic lives in /tests/verify.py (delegated here); that script
# prints a readable failure list and exits 0 only when every check passes.
# Reward is binary: exactly "1" or "0" in /logs/verifier/reward.txt.
#
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u
mkdir -p /logs/verifier

if python3 /tests/verify.py; then
  echo "1" > /logs/verifier/reward.txt
else
  echo "0" > /logs/verifier/reward.txt
fi
exit 0