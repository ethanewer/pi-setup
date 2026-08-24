#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/drop.txt ]; then
  content=$(cat /app/drop.txt | tr -d '\r')
  if [ "$content" = "dropbear-secret-here" ]; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt