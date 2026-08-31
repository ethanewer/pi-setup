#!/usr/bin/env bash
# Oracle for tasks/wick-lantern (executes-deliverable).
# Writes the Jupyter Server config deliverable (the real work), then
# smoke-tests it by ACTUALLY launching jupyter server: bind, non-loopback
# reachability, and tokenless /api/status. Never reads /tests.
set -euo pipefail

CFG="/app/jupyter_config.py"

cat > "$CFG" <<'PY'
"""Wick Lantern lightroom Jupyter Server configuration.

Binds all interfaces (0.0.0.0), takes the listen port from $LANTERN_PORT
(integer 1..65535, default 7412), and disables token/password auth for
tokenless lab probes.
"""
import os

c = get_config()


def _port():
    raw = os.environ.get("LANTERN_PORT", "")
    try:
        p = int(raw)
    except (TypeError, ValueError):
        p = 7412
    return p if 1 <= p <= 65535 else 7412


port = _port()

c.ServerApp.ip = "0.0.0.0"
c.ServerApp.port = port
c.ServerApp.open_browser = False
c.ServerApp.allow_remote_access = True
c.ServerApp.token = ""
c.ServerApp.password = ""

c.NotebookApp.ip = "0.0.0.0"
c.NotebookApp.port = port
c.NotebookApp.open_browser = False
c.NotebookApp.allow_remote_access = True
c.NotebookApp.token = ""
c.NotebookApp.password = ""
PY

chmod +x "$CFG"

# ---------------------------------------------------------------- smoke test
echo "[solve] smoke: launch jupyter with LANTERN_PORT=7931" >&2
pkill -f "jupyter-server" 2>/dev/null || true
mkdir -p /tmp/wick_smoke
LANTERN_PORT=7931 jupyter server \
    --config="$CFG" --no-browser --allow-root \
    --ServerApp.root_dir=/tmp/wick_smoke >/tmp/wick_smoke.log 2>&1 &
JPID=$!

ok=""
for i in $(seq 1 60); do
    if python3 - <<'PY'
import socket
try:
    s = socket.create_connection(("127.0.0.1", 7931), 1); s.close()
    raise SystemExit(0)
except OSError:
    raise SystemExit(1)
PY
    then ok=1; break; fi
    sleep 0.5
done
if [ -z "$ok" ]; then
    echo "smoke: server never bound port 7931" >&2
    tail -20 /tmp/wick_smoke.log >&2 || true
    kill "$JPID" 2>/dev/null || true
    exit 1
fi

# Tokenless /api/status must answer 200.
code="$(python3 - <<'PY'
import urllib.request, urllib.error
try:
    with urllib.request.urlopen("http://127.0.0.1:7931/api/status", timeout=5) as r:
        print(r.status)
except urllib.error.HTTPError as e:
    print(e.code)
except Exception as e:
    print("ERR:%r" % e)
PY
)"
if [ "$code" != "200" ]; then
    echo "smoke: /api/status answered $code (expected 200)" >&2
    kill "$JPID" 2>/dev/null || true
    exit 1
fi

# Must be reachable on the machine's non-loopback address (all-interfaces bind).
ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
if [ -n "$ip" ]; then
    if ! python3 - "$ip" <<'PY'
import socket, sys
try:
    s = socket.create_connection((sys.argv[1], 7931), 3); s.close()
    raise SystemExit(0)
except OSError:
    raise SystemExit(1)
PY
    then
        echo "smoke: not reachable on non-loopback $ip:7931" >&2
        kill "$JPID" 2>/dev/null || true
        exit 1
    fi
fi

kill "$JPID" 2>/dev/null || true
pkill -f "jupyter-server" 2>/dev/null || true
wait "$JPID" 2>/dev/null || true

echo "wick-lantern deliverable written and smoke-tested: $CFG"
ls -l "$CFG"
