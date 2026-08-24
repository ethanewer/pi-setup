#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/bottle_app.py ]; then
  ok=0
  python3 /app/bottle_app.py >/dev/null 2>&1 &
  SRV=$!
  # wait for server
  for i in $(seq 1 40); do
    if curl -s http://127.0.0.1:8080/session >/dev/null 2>&1; then break; fi
    sleep 0.25
  done
  J=p
  rm -f /tmp/ck
  r1=$(curl -s -c /tmp/ck http://127.0.0.1:8080/session 2>/dev/null)
  r2=$(curl -s -b /tmp/ck -c /tmp/ck http://127.0.0.1:8080/session 2>/dev/null)
  r3=$(curl -s -b /tmp/ck -c /tmp/ck http://127.0.0.1:8080/session 2>/dev/null)
  if [ "$r1" = "1" ] && [ "$r2" = "2" ] && [ "$r3" = "3" ]; then
    ok=1
  fi
  kill $SRV 2>/dev/null
  if [ "$ok" = "1" ]; then reward=1; fi
fi
echo "$reward" > /logs/verifier/reward.txt
