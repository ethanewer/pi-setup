#!/bin/bash
# Verifier for item-026-main: CRLF header injection regression.
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
cd /app

# Run the hidden copy of the regression; do NOT trust the agent's copy.
if [ -f /tests/regression_check.py ]; then
  cp /tests/regression_check.py /tmp/rr_check.py
else
  cp /app/regression_check.py /tmp/rr_check.py
fi

python3 /tmp/rr_check.py > /tmp/rr_out.txt 2>&1

reward=0
if grep -q 'REGRESSION OK' /tmp/rr_out.txt; then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt