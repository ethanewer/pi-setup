#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/display_dimensions.txt ]; then
  got=$(cat /app/display_dimensions.txt | tr -d '\r\n ')
  if [ "$got" = "1024x768" ]; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt