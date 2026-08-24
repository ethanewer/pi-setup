#!/bin/bash

reward=0
if [ -f /app/lines.txt ]; then
  got=$(cat /app/lines.txt)
  if [ "$got" = "alpha"$'\n'"gamma"$'\n'"beta" ]; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt