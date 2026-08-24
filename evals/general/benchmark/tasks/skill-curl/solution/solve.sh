#!/bin/bash
set -uo pipefail
cd /app
python3 -m http.server 8090 --directory /app/webroot >/dev/null 2>&1 &
SRV=$!
sleep 1
curl -s http://127.0.0.1:8090/public/sample.json -o /app/fetched.json
kill "$SRV" >/dev/null 2>&1 || true
if [ ! -s /app/fetched.json ]; then
  echo "FAILED_TO_FETCH" > /app/fetched.json
fi