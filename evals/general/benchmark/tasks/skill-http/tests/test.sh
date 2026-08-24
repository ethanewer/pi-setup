#!/bin/bash
reward=0
mkdir -p /logs/verifier
if [ -f /app/http.txt ]; then
  if [ "$(cat /app/http.txt)" == "200
world" ]; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt