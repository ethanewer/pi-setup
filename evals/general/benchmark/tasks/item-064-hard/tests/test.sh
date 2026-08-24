#!/bin/bash
# item-064-main verifier entry point.
mkdir -p /logs/verifier

# Always write a reward file.
reward=0.0

if [ ! -f /app/output.json ]; then
  echo "$reward" > /logs/verifier/reward.txt
  exit 0
fi

# The rules.json must be populated (not the empty stub) with both sections and
# must be valid JSON that the engine accepts.
if [ ! -f /app/rules.json ]; then
  echo "$reward" > /logs/verifier/reward.txt
  exit 0
fi

# The shipped move generator must be self-contained: python-chess is installed
# so the independent checker can compute reference move-sets, but /app/moves.py
# must not import it.  Reject agents that cheat by wrapping the library.
if [ -f /app/moves.py ]; then
  if grep -Eq '[^[:alnum:]_]import[[:space:]]+chess|from[[:space:]]+chess[[:space:]]+import|chess\.' /app/moves.py; then
    echo "$reward" > /logs/verifier/reward.txt
    exit 0
  fi
fi

python3 /tests/test_check.py > /tmp/check.log 2>&1
# test_check.py writes the reward itself; mirror it if missing.
if [ ! -f /logs/verifier/reward.txt ]; then
  echo "$reward" > /logs/verifier/reward.txt
fi
exit 0