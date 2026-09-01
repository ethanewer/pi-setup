#!/bin/bash
reward=0
mkdir -p /logs/verifier
if [ -f /app/sum.txt ]; then
  if [ "$(cat /app/sum.txt)" == "40" ]; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt