#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/assembled.txt ]; then
  s=$(cat /app/assembled.txt | tr -d '\r\n ')
  if [ "$s" = "ABCDEFGHIJK" ]; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt