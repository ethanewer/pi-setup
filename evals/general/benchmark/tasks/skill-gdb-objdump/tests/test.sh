#!/bin/bash
mkdir -p /logs/verifier

reward=0
if [ -f /app/secret.txt ]; then
  if [ "$(cat /app/secret.txt | tr -d '\r\n')" == "OBJD-REVEAL-77" ]; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt