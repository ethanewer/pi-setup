#!/bin/bash
reward=0
mkdir -p /logs/verifier
if [ -f /app/serve.py ]; then
  pkill -f '/app/serve.py' 2>/dev/null || true
  sleep 2
  pkill -f '/app/serve.py' 2>/dev/null || true
  python3 /app/serve.py >/dev/null 2>&1 &
  SRVPID=$!
  ping=""
  info=""
  # retry until the server answers or timeout (~30s)
  for i in $(seq 1 30); do
    ping=$(curl -s --max-time 2 http://127.0.0.1:8090/ping 2>/dev/null)
    info=$(curl -s --max-time 2 http://127.0.0.1:8090/info 2>/dev/null)
    if [ -n "$ping" ] || [ -n "$info" ]; then
      break
    fi
    if ! kill -0 "$SRVPID" 2>/dev/null; then
      break
    fi
    sleep 1
  done
  pkill -f '/app/serve.py' 2>/dev/null || true
  if [ "$ping" == "pong" ] && [ "$info" == "{\"app\":\"bench\"}" ]; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt
