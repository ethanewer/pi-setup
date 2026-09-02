#!/bin/bash
# juniper-wharf harness entrypoint: bring up the Revetment object-store S3
# endpoint and its control-plane head (loopback-only) before running the
# harness command (the agent session or the verifier), then exec it.
set -e

nohup python3 /app/object_server.py --root /app/realm --port 9000 --bind 127.0.0.1 \
   >/tmp/object_store.log 2>&1 &
nohup python3 /app/control_server.py --port 9001 --bind 127.0.0.1 \
   --def-access wharfmaster --def-secret wharfmaster \
   >/tmp/control_head.log 2>&1 &

python3 - <<'PY'
import time, urllib.request
for _ in range(40):
    ok = True
    for port in (9000, 9001):
        try:
            urllib.request.urlopen("http://127.0.0.1:%d/health" % port, timeout=1)
        except Exception:
            ok = False
    if ok:
        break
    time.sleep(0.25)
PY

exec "$@"