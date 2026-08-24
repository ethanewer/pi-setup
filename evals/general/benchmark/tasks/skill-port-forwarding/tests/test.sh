#!/bin/bash
mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0

# clear any pre-existing listener / leftover tunnel on the forwarding port
pkill -f 'socat TCP-LISTEN:8090' 2>/dev/null
pkill -f 'socat TCP-LISTEN:8090 ' 2>/dev/null
pkill -f 'http.server 9097' 2>/dev/null
sleep 0.4

rm -rf /tmp/fwdserve
mkdir -p /tmp/fwdserve
echo 'FORWARD_MARKER_XYZW' > /tmp/fwdserve/marker.txt

if [ -f "$APP/forward.sh" ]; then
  ( cd /tmp/fwdserve && python3 -m http.server 9097 --bind 127.0.0.1 >/dev/null 2>&1 ) &
  sleep 1.0
  # run the agent's forward script as a background job (it must set up the
  # tunnel; whether it returns immediately or keeps its listener in the
  # foreground, the listener below is established and reachable).
  bash "$APP/forward.sh" >/dev/null 2>&1 &
  sleep 1.5
  body=$(curl -s --max-time 4 http://127.0.0.1:8090/marker.txt 2>/dev/null | tr -d '\r\n')
  if [ "$body" = "FORWARD_MARKER_XYZW" ]; then
    reward=1
  fi
fi

pkill -f 'http.server 9097' 2>/dev/null
pkill -f 'socat TCP-LISTEN:8090' 2>/dev/null
printf '%s' "$reward" > /logs/verifier/reward.txt