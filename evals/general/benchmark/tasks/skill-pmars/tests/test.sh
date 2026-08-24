#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/length.txt ] && [ -f /app/warrior.red ] && [ -x /app/pmars ]; then
  expected=$(/app/pmars /app/warrior.red 2>/dev/null | sed -n 's/.*(length \([0-9]*\)).*/\1/p' | head -1)
  got=$(sed -e 's/[[:space:]]*$//' /app/length.txt)
  if [ -n "$expected" ] && [ "$got" = "$expected" ]; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt