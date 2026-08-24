#!/bin/bash
reward=0
mkdir -p /logs/verifier
if [ -f /app/serve.py ]; then
  pkill -f '/app/serve.py' 2>/dev/null
  sleep 1
  python3 /app/serve.py >/dev/null 2>&1 &
  sleep 2
  ping=$(curl -s --max-time 3 http://127.0.0.1:8090/ping)
  info=$(curl -s --max-time 3 http://127.0.0.1:8090/info)
  pkill -f '/app/serve.py' 2>/dev/null
  if [ "$ping" == "pong" ] && [ "$info" == "{\"app\":\"bench\"}" ]; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt