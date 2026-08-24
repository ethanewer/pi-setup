#!/bin/bash
mkdir -p /logs/verifier
reward=0

if [ -f /app/legacy.py ]; then
  cd /app || exit 1
  expected="sum=55 count=10 avg=5.5"
  # (a) run under python3, must succeed and print exactly expected
  live=$(python3 /app/legacy.py 2>/dev/null)
  if [ "$live" = "$expected" ]; then
    # (b) out.txt must exist with matching line
    if [ -f /app/out.txt ]; then
      out=$(sed -e 's/[[:space:]]*$//' /app/out.txt)
      if [ "$out" = "$expected" ]; then
        reward=1
      fi
    fi
  fi
fi
echo "$reward" > /logs/verifier/reward.txt