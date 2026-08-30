#!/usr/bin/env bash
# Hidden case A: the restored /usr/bin/curl must be genuinely functional on an
# arbitrary (different) URL, not a one-off wrapper for one canned page.
set -uo pipefail
FW="$1"; CH="$2"
PORT=8874
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory /app/origin >/tmp/h1.log 2>&1 &
M=$!
for _ in $(seq 1 20); do
  sleep 0.3
  python3 -c "import socket,sys
try:
  s=socket.socket(); s.settimeout(.4); s.connect(('127.0.0.1',$PORT)); s.close(); sys.exit(0)
except: sys.exit(1)" && break
done
/usr/bin/curl -fsS "http://127.0.0.1:$PORT/telemetry/status.json" -o /tmp/h1.out
rc=$?
kill "$M" 2>/dev/null || true
if [ "$rc" = 0 ] && cmp -s /tmp/h1.out /app/origin/telemetry/status.json; then
  echo "  (curl fetches a second, different URL correctly)"
  exit 0
fi
echo "  (curl did not fetch the second URL correctly)" >&2
exit 1