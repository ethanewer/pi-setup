#!/bin/bash
# ember-atlas harness entrypoint: bring up the loopback-only Ridgetop model
# hub before running the harness command (agent session or verifier).
set -e

nohup python3 /app/hub_server.py --root /app/hub --port 8000 --bind 127.0.0.1 \
   >/tmp/hub_server.log 2>&1 &

python3 - <<'PY'
import time, urllib.request
for _ in range(40):
    try:
        urllib.request.urlopen("http://127.0.0.1:8000/health", timeout=1)
        break
    except Exception:
        time.sleep(0.25)
PY

exec "$@"
