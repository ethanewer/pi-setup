#!/bin/bash
mkdir -p /logs/verifier

reward=0
if [ -f /app/settings.json ]; then
  out=$(python3 /app/server_app.py 2>/dev/null | tr -d ' \t\r\n')
  if [ "$out" = "STARTED" ]; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt