#!/bin/bash
mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0

# clear any pre-existing listener / leftover tunnel on the forwarding port
# AND on the source port: the agent may have left its own test server on
# 9097 (any cmdline, not just `python3 -m http.server`), which would
# shadow the verifier's server below.
free_port() {
  if command -v fuser >/dev/null 2>&1; then
    fuser -k "$1/tcp" 2>/dev/null || true
  fi
  pkill -f "socat TCP-LISTEN:$1" 2>/dev/null
  pkill -f "http.server $1" 2>/dev/null
}
free_port 8090
free_port 9097
sleep 0.5

rm -rf /tmp/fwdserve
mkdir -p /tmp/fwdserve
echo 'FORWARD_MARKER_XYZW' > /tmp/fwdserve/marker.txt

if [ -f "$APP/forward.sh" ]; then
  ( cd /tmp/fwdserve && python3 -m http.server 9097 --bind 127.0.0.1 >/dev/null 2>&1 ) &
  # wait until the source server actually answers before testing the tunnel
  for _ in 1 2 3 4 5 6 7 8; do
    if curl -s --max-time 1 http://127.0.0.1:9097/marker.txt >/dev/null 2>&1; then break; fi
    sleep 0.5
  done
  # run the agent's forward script as a background job (it must set up the
  # tunnel; whether it returns immediately or keeps its listener in the
  # foreground, the listener below is established and reachable).
  bash "$APP/forward.sh" >/dev/null 2>&1 &
  sleep 1.5
  body=""
  for _ in 1 2 3; do
    body=$(curl -s --max-time 4 http://127.0.0.1:8090/marker.txt 2>/dev/null | tr -d '\r\n')
    [ "$body" = "FORWARD_MARKER_XYZW" ] && break
    sleep 0.5
  done
  if [ "$body" = "FORWARD_MARKER_XYZW" ]; then
    reward=1
  fi
fi

pkill -f 'http.server 9097' 2>/dev/null
pkill -f 'socat TCP-LISTEN:8090' 2>/dev/null
printf '%s' "$reward" > /logs/verifier/reward.txt