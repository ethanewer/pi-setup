#!/bin/bash
mkdir -p /logs/verifier

reward=0
if [ -f /app/answer.txt ]; then
  ans=$(tr '[:lower:]' '[:upper:]' < /app/answer.txt | tr -d '[:space:]\r' | tr -s 'A-Z')
  if [ "$ans" = "SPL" ]; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt