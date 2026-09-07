#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

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
