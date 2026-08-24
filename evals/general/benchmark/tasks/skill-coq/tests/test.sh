#!/bin/bash
mkdir -p /logs/verifier

reward=0
if [ -f /app/answer.txt ]; then
  vals=$(tr -d '[:space:]\r' < /app/answer.txt)
  if [ "$vals" = "45" ]; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt