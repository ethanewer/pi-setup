#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/result.txt ]; then
  got=$(sed -e 's/[[:space:]]*$//' /app/result.txt)
  if [ "$got" = "HELLO WORLD" ]; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt