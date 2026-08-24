#!/bin/bash

# Verifier for item-073-hard. Must always write /logs/verifier/reward.txt.
mkdir -p /logs/verifier

if [ -f /app/result.npz ] && [ -f /app/optimize.py ]; then
  reward=$(python3 /tests/check_073_hard.py 2>/dev/null || echo 0)
else
  reward=0
fi

case "$reward" in
  ""|*[!0-9.]*) reward=0 ;;
esac

echo "$reward" > /logs/verifier/reward.txt