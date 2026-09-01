#!/bin/bash
# Oracle for tasks/ferrite-strait.
#
# Does the real work: writes the launcher program /app/launch.sh, the live
# status program /app/status.cgi and the default /app/kiosk.conf, then runs
# the launcher once (default config) and probes VNC + web + live status to
# prove the kiosk is really up. Never reads /tests.
set -eu

# --------------------------------------------------------------------------
# 1) /app/status.cgi -- the live status program (executed per config by
#    launch.sh as the web plane's /cgi-bin/status.json handler).
# --------------------------------------------------------------------------
cat > /app/status.cgi <<'SH'
#!/bin/sh
# Live kiosk status -> JSON. Parameterised at install time by launch.sh via
# the KIOSK_STATE env-var file (written next to the web root).
# shellcheck disable=SC1090
. "$KIOSK_STATE"
PID=$(cat "$KIOSK_PIDFILE" 2>/dev/null || echo 0)
ALIVE=0
kill -0 "$PID" 2>/dev/null && ALIVE=1
UP=0
if [ "$ALIVE" = 1 ]; then
    NOW=$(date +%s)
    UP=$((NOW - KIOSK_STARTED))
fi
printf 'Content-Type: application/json\r\n\r\n'
printf '{"marker":"%s","status_title":"%s","vnc_display":%d,"vnc_port":%d,"web_port":%d,"mem_mib":%d,"qemu_pid":%d,"alive":%d,"uptime_sec":%d}\n' \
    "$KIOSK_MARKER" "$KIOSK_TITLE" "$KIOSK_DISPLAY" "$KIOSK_VNCPORT" \
    "$KIOSK_WEBPORT" "$KIOSK_MEM" "$PID" "$ALIVE" "$UP"
SH
chmod +x /app/status.cgi

# --------------------------------------------------------------------------
# 2) The launcher program /app/launch.sh (executes-deliverable).
# --------------------------------------------------------------------------
cat > /app/launch.sh <<'SH'
#!/bin/bash
# Bring the Ferrite kiosk up in the background: emulated machine with VNC on
# the config's display (default :1) + monitoring web plane on the config's
# port (default 80) with a live /cgi-bin/status.json endpoint.
# Usage: launch.sh [config.json]   (no arg -> /app/kiosk.conf)
set -eu

CFG="${1:-/app/kiosk.conf}"
eval "$(python3 - "$CFG" <<'PY'
import json, sys
c = json.load(open(sys.argv[1]))
keys = ["vnc_display", "web_port", "marker", "mem_mib", "pidfile",
        "web_pidfile", "web_dir", "status_title"]
for k in keys:
    print("CFG_%s=%s" % (k.upper(), repr(str(c.get(k, "")))))
PY
)"

CFG_VNC_DISPLAY="${CFG_VNC_DISPLAY:-1}"
CFG_WEB_PORT="${CFG_WEB_PORT:-80}"
CFG_MEM_MIB="${CFG_MEM_MIB:-256}"
VNC_TCP=$((5900 + CFG_VNC_DISPLAY))

# Idempotent teardown: kill anything a previous run of this config started.
for pf in "$CFG_PIDFILE" "$CFG_WEB_PIDFILE"; do
    [ -n "$pf" ] && [ -f "$pf" ] && kill "$(cat "$pf" 2>/dev/null)" 2>/dev/null || true
done
rm -f "$CFG_PIDFILE" "$CFG_WEB_PIDFILE"

# Web plane: static monitor page + live CGI status endpoint.
mkdir -p "$CFG_WEB_DIR/cgi-bin"
cat > "$CFG_WEB_DIR/index.html" <<HTML
<!doctype html><html><head><meta charset=utf-8><title>${CFG_STATUS_TITLE}</title></head>
<body><h1>${CFG_STATUS_TITLE}</h1><p>kiosk marker: ${CFG_MARKER}</p><p>vnc display :${CFG_VNC_DISPLAY}</p><p>state: running in background</p></body></html>
HTML
cat > "$CFG_WEB_DIR/cgi-bin/state.env" <<ENV
KIOSK_MARKER=$(printf '%q' "$CFG_MARKER")
KIOSK_TITLE=$(printf '%q' "$CFG_STATUS_TITLE")
KIOSK_DISPLAY=$CFG_VNC_DISPLAY
KIOSK_VNCPORT=$VNC_TCP
KIOSK_WEBPORT=$CFG_WEB_PORT
KIOSK_MEM=$CFG_MEM_MIB
KIOSK_PIDFILE=$(printf '%q' "$CFG_PIDFILE")
KIOSK_STARTED=$(date +%s)
ENV
chmod 644 "$CFG_WEB_DIR/cgi-bin/state.env"
install -m 755 /app/status.cgi "$CFG_WEB_DIR/cgi-bin/status.json"

KIOSK_STATE="$CFG_WEB_DIR/cgi-bin/state.env" \
KIOSK_PIDFILE="$CFG_PIDFILE" \
    /usr/bin/busybox httpd -f -p "$CFG_WEB_PORT" -h "$CFG_WEB_DIR" >/dev/null 2>&1 &
echo $! > "$CFG_WEB_PIDFILE"

# Emulated machine in the background (TCG, firmware stage: no -kernel).
qemu-system-x86_64 -m "$CFG_MEM_MIB" \
    -display none \
    -vnc ":$CFG_VNC_DISPLAY" \
    -nic none \
    >/dev/null 2>&1 &
QPID=$!
echo "$QPID" > "$CFG_PIDFILE"

# Poll until kiosk (qemu alive + vnc + web) is fully reachable.
up=0
for _ in $(seq 1 90); do
  if ! kill -0 "$QPID" 2>/dev/null; then
      echo "QEMU exited during bring-up" >&2; exit 3
  fi
  if python3 - "$VNC_TCP" "$CFG_WEB_PORT" <<'PY'; then
import socket, sys
def tcp_ok(p):
    s = socket.socket(); s.settimeout(0.5)
    try:
        return s.connect_ex(("127.0.0.1", p)) == 0
    finally:
        s.close()
if not tcp_ok(int(sys.argv[1])): raise SystemExit(1)
if not tcp_ok(int(sys.argv[2])): raise SystemExit(1)
PY
      up=1; break
  fi
  sleep 1
done

if [ "$up" -ne 1 ]; then
  echo "kiosk did not become reachable in time" >&2
  exit 4
fi

echo "KIOSK READY vnc=127.0.0.1:$VNC_TCP web=127.0.0.1:$CFG_WEB_PORT pid=$QPID"
exit 0
SH
chmod +x /app/launch.sh

# --------------------------------------------------------------------------
# 3) The default config deliverable (VNC display 1, standard web port 80).
# --------------------------------------------------------------------------
cat > /app/kiosk.conf <<'JSON'
{
  "vnc_display": 1,
  "web_port": 80,
  "marker": "ferrite-live-1",
  "mem_mib": 256,
  "pidfile": "/tmp/ferrite_vm.pid",
  "web_pidfile": "/tmp/ferrite_web.pid",
  "web_dir": "/tmp/ferrite_monitor",
  "status_title": "Ferrite kiosk monitor"
}
JSON

# --------------------------------------------------------------------------
# 4) Prove the launcher really brings the kiosk up (then stand down again so
#    the oracle leaves no stray processes).
# --------------------------------------------------------------------------
bash /app/launch.sh
python3 - <<'PY'
import json, socket, urllib.request
st = json.load(open("/app/kiosk.conf"))
pid = int(open(st["pidfile"]).read().strip())
assert pid > 0
with urllib.request.urlopen("http://127.0.0.1:%d/cgi-bin/status.json" % st["web_port"], timeout=5) as r:
    live = json.loads(r.read().decode())
assert live["qemu_pid"] == pid and live["alive"] == 1, live
assert live["vnc_port"] == 5900 + st["vnc_display"], live
s = socket.socket(); s.settimeout(3)
s.connect(("127.0.0.1", 5900 + st["vnc_display"]))
assert s.recv(12).startswith(b"RFB "), "no RFB greeting"
s.close()
print("oracle probe ok:", live)
PY

# stand down (the verifier re-runs launch.sh itself, idempotently)
kill "$(cat /app/kiosk.conf | python3 -c 'import json,sys; print(json.load(sys.stdin)["pidfile"])' | xargs cat)" 2>/dev/null || true
kill "$(cat /tmp/ferrite_web.pid)" 2>/dev/null || true
rm -f /tmp/ferrite_vm.pid /tmp/ferrite_web.pid

echo "deliverables:"
ls -la /app/launch.sh /app/kiosk.conf /app/status.cgi
