#!/bin/bash
# drift-quarry harness entrypoint: bring up the loopback-only Cirque object
# store before running the harness command (agent session or verifier).
set -e

nohup python3 /app/object_server.py --root /app/realm --port 9000 --bind 127.0.0.1 \
   >/tmp/object_store.log 2>&1 &

python3 - <<'PY'
import time, urllib.request
for _ in range(40):
    try:
        urllib.request.urlopen("http://127.0.0.1:9000/health", timeout=1)
        break
    except Exception:
        time.sleep(0.25)
PY

exec "$@"
