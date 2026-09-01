#!/bin/bash
reward=0
mkdir -p /logs/verifier
if [ -f /app/answer.txt ]; then
  if [ "$(cat /app/answer.txt)" == "10000" ]; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt