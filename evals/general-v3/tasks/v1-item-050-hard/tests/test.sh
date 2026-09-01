#!/bin/bash
mkdir -p /logs/verifier
reward=0

if ! nginx -t >/tmp/nginx_t.log 2>&1; then
  echo "$reward" > /logs/verifier/reward.txt
  exit 0
fi

if ! pgrep -x nginx >/dev/null 2>&1; then
  nginx 2>/dev/null
else
  nginx -s reload 2>/dev/null
fi

up=0
for i in $(seq 1 30); do
  if curl -s -o /dev/null "http://127.0.0.1:8000/api" 2>/dev/null; then
    up=1; break
  fi
  sleep 0.2
done
if [ "$up" != "1" ]; then
  echo "$reward" > /logs/verifier/reward.txt
  exit 0
fi

ok=1

# /api
if [ "$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8000/api)" != "200" ]; then ok=0; fi
na429=0; na200=0
for i in $(seq 1 16); do
  c=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8000/api)
  if [ "$c" = "429" ]; then na429=$((na429 + 1)); elif [ "$c" = "200" ]; then na200=$((na200 + 1)); fi
done
if [ "$na429" -lt 3 ]; then ok=0; fi
if [ "$na200" -lt 1 ]; then ok=0; fi

# /auth
if [ "$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8000/auth)" != "200" ]; then ok=0; fi
nb429=0
for i in $(seq 1 8); do
  c=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8000/auth)
  if [ "$c" = "429" ]; then nb429=$((nb429 + 1)); fi
done
if [ "$nb429" -lt 3 ]; then ok=0; fi

# spaced refill
sleep 1.6
if [ "$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8000/api)" != "200" ]; then ok=0; fi
if [ "$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8000/auth)" != "200" ]; then ok=0; fi

# log
LOG=/var/log/nginx/api_access.log
if [ ! -f "$LOG" ] || [ ! -s "$LOG" ]; then
  ok=0
else
  if ! grep -qE '[[:space:]]200([[:space:]]|$)' "$LOG"; then ok=0; fi
  if ! grep -qE '[[:space:]]429([[:space:]]|$)' "$LOG"; then ok=0; fi
fi

echo "$ok" > /logs/verifier/reward.txt