#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/solve.py ] && [ -f /app/cleanres.py ]; then
  rm -f /app/cleaned.txt
  if python3 /app/solve.py 2>/dev/null; then
    if [ -f /app/cleaned.txt ]; then
      content=$(tr -d '\r\n' < /app/cleaned.txt 2>/dev/null)
      if [ "$content" = "cleaned" ]; then
        reward=1
      fi
    fi
  fi
fi
echo "$reward" > /logs/verifier/reward.txt