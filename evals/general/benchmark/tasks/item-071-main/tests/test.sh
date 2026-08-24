#!/bin/bash

# Verifier for item-071-main. Writes 0..1 reward to /logs/verifier/reward.txt.
# Delegates the heavy lifting to /tests/verify.py (hidden from the agent).

mkdir -p /logs/verifier

reward=0
if [ -f /app/data/tokens.pt ] && [ -f /app/reference.py ]; then
  out=$(python3 /tests/verify.py)
  if [ "$out" = "1.0" ]; then
    reward=1
  elif [ "$out" = "0.5" ]; then
    reward=0.5
  else
    reward=0
  fi
fi
echo "$reward" > /logs/verifier/reward.txt
exit 0