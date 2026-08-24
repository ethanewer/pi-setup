#!/bin/bash
reward=0
mkdir -p /logs/verifier
if [ -f /app/header.txt ]; then
  if [ "$(cat /app/header.txt)" == "secret42" ]; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt