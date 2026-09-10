#!/bin/bash
#
# escutcheon-cable verifier.
# Brings the distributed cart stack up from the agent's deliverable
# /app/up.sh, then drives the visible plus hidden request scenarios through
# the frontend, parses the spans collected by the local collector and the
# structured JSON logs, and writes 1/0 to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
echo 0 > /logs/verifier/reward.txt

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

echo "bringing the cart stack up via /app/up.sh"
if ! timeout 120 bash /app/up.sh >/tmp/up.out 2>&1; then
  echo "FAULT: deliverable /app/up.sh did not bring the stack up; scoring 0"
  tail -30 /tmp/up.out >&2 || true
  echo 0 > /logs/verifier/reward.txt
  exit 0
fi

if timeout 400 python3 /tests/verify.py; then
  echo "ALL SCENARIOS PASSED"
  echo 1 > /logs/verifier/reward.txt
else
  echo "verify.py reported failures above; scoring 0"
  echo 0 > /logs/verifier/reward.txt
fi
exit 0
