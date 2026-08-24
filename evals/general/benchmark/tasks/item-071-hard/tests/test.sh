#!/bin/bash

# Verifier for item-071-hard. Writes 0..1 reward to /logs/verifier/reward.txt.

mkdir -p /logs/verifier

reward=0
if [ -f /app/data/tokens.pt ] && [ -f /app/reference.py ]; then
  out=$(python3 /tests/verify.py)
  case "$out" in
    1.0) reward=1 ;;
    0.5) reward=0.5 ;;
    *)   reward=0 ;;
  esac
fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
