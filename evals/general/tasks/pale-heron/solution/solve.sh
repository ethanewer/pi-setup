#!/usr/bin/env bash
# Oracle for pale-heron. Produces the /app deliverable (real work) and
# smoke-tests it by actually launching the server. Never reads /tests.
set -euo pipefail

cat > /app/notebook_server_config.py <<'PY'
"""Harborlight CI notebook runner config.

Port comes from /app/nb_deploy.json at load time (integer or decimal string,
1024..65535); anything invalid falls back to the default 7741. Loopback-only
binding, no port drifting (port_retries=0), no browser, tokenless auth.
"""
import json
import os

c = get_config()

DEFAULT_PORT = 7741
DESCRIPTOR = "/app/nb_deploy.json"


def _resolve_port():
    raw = None
    try:
        with open(DESCRIPTOR, "r", encoding="utf-8") as fh:
            data = json.load(fh)
        if isinstance(data, dict):
            raw = data.get("port", DEFAULT_PORT)
    except (OSError, ValueError):
        raw = None
    try:
        port = int(raw)
    except (TypeError, ValueError):
        return DEFAULT_PORT
    if 1024 <= port <= 65535:
        return port
    return DEFAULT_PORT


_port = _resolve_port()

c.ServerApp.ip = "127.0.0.1"
c.ServerApp.port = _port
c.ServerApp.port_retries = 0
c.ServerApp.open_browser = False
c.ServerApp.token = ""
c.ServerApp.password = ""

c.NotebookApp.ip = "127.0.0.1"
c.NotebookApp.port = _port
c.NotebookApp.port_retries = 0
c.NotebookApp.open_browser = False
c.NotebookApp.token = ""
c.NotebookApp.password = ""
PY

chmod +x /app/notebook_server_config.py

# ---- smoke test: config must load and the server must bind + answer 200 ----
python3 -m py_compile /app/notebook_server_config.py

mkdir -p /tmp/ph_smoke
jupyter server --config=/app/notebook_server_config.py --no-browser --allow-root \
    --ServerApp.root_dir=/tmp/ph_smoke >/tmp/ph_smoke.log 2>&1 &
JPID=$!
ok=""
for i in $(seq 1 40); do
    if python3 - <<'PY'
import socket
try:
    s = socket.create_connection(("127.0.0.1", 8100), 1)
    s.close()
    raise SystemExit(0)
except OSError:
    raise SystemExit(1)
PY
    then ok=1; break; fi
    sleep 0.5
done
if [ -z "$ok" ]; then
    echo "smoke failed: server never bound 127.0.0.1:8100" >&2
    cat /tmp/ph_smoke.log >&2 || true
    kill "$JPID" 2>/dev/null || true
    exit 1
fi
code="$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8100/api/status || echo ERR)"
kill "$JPID" 2>/dev/null || true
wait "$JPID" 2>/dev/null || true
pkill -f "jupyter-server" 2>/dev/null || true
if [ "$code" != "200" ]; then
    echo "smoke failed: /api/status gave $code (want 200)" >&2
    exit 1
fi

echo "pale-heron oracle done -> /app/notebook_server_config.py"
