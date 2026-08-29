#!/usr/bin/env bash
# willow-bridge oracle. Produces the two /app deliverables (real work), then
# smoke-tests each by RUNNING them. Never reads /tests. Literal /app paths.
set -euo pipefail

# ---------------------------------------------------------------- 1) Jupyter config
cat > /app/jupyter_server_config.py <<'PY'
"""Willow Bridge loopback-only Jupyter Server configuration.

Binding: 127.0.0.1 only. Port: $WILLOW_NOTE_PORT (integer 1..65535) else 8666.
Browser is not opened; token/password are empty so loopback auth is disabled.
"""
import os

c = get_config()

def _port():
    raw = os.environ.get("WILLOW_NOTE_PORT", "8666")
    try:
        p = int(raw)
    except (TypeError, ValueError):
        p = 8666
    return p if 1 <= p <= 65535 else 8666

port = _port()

c.ServerApp.ip = "127.0.0.1"
c.ServerApp.port = port
c.ServerApp.open_browser = False
c.ServerApp.token = ""
c.ServerApp.password = ""

c.NotebookApp.ip = "127.0.0.1"
c.NotebookApp.port = port
c.NotebookApp.open_browser = False
c.NotebookApp.token = ""
c.NotebookApp.password = ""
PY

# ---------------------------------------------------------------- 2) gawk classifier
cat > /app/ipv4_octet.awk <<'AWK'
# Willow Bridge strict IPv4 classifier.
# One self-contained IPv4 ERE: octets 0..255, no leading zeros, four groups,
# full-string anchored (so it is not part of a longer alphanumeric token).
BEGIN {
    ip = "^([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])" \
         "(\\.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])){3}$"
}
{
    line = $0
    sub(/^[ \t\r\n]+/, "", line)
    sub(/[ \t\r\n]+$/, "", line)
    if (line ~ ip)
        print "VALID\t" line
    else
        print "INVALID\t" line
}
AWK
chmod +x /app/ipv4_octet.awk

# ---------------------------------------------------------------- smoke tests (real runs)
echo "[solve] smoke: gawk over sample corpus" >&2
gawk -f /app/ipv4_octet.awk /app/sample_ips.txt > /tmp/smoke_ips.out 2>&1
[ -s /tmp/smoke_ips.out ] || { echo "smoke: awk produced no output" >&2; exit 1; }

echo "[solve] smoke: jupyter server config loads + binds" >&2
mkdir -p /tmp/wb_smoke
WILLOW_NOTE_PORT=8791 jupyter server \
    --config=/app/jupyter_server_config.py --no-browser --allow-root \
    --ServerApp.root_dir=/tmp/wb_smoke >/tmp/wb_smoke.log 2>&1 &
JPID=$!
ok=""
for i in $(seq 1 30); do
    if python3 - <<'PY'
try:
    import socket
    s = socket.create_connection(("127.0.0.1", 8791), 1); s.close()
    raise SystemExit(0)
except OSError:
    raise SystemExit(1)
PY
    then ok=1; break; fi
    sleep 0.4
done
[ -n "$ok" ] || { echo "smoke: jupyter did not bind 8791" >&2; kill "$JPID" 2>/dev/null || true; exit 1; }
kill "$JPID" 2>/dev/null || true
pkill -f "jupyter-server" 2>/dev/null || true
wait "$JPID" 2>/dev/null || true

echo "willow-bridge deliverables written and smoke-tested" >&2
