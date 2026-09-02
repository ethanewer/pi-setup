#!/usr/bin/env bash
# Hidden case B: restore_curl.sh must be idempotent and tolerant of stray/malformed
# arguments, and leave a genuine executable curl that still fetches true content.
set -uo pipefail
FW="$1"; CH="$2"
bash /app/restore_curl.sh --refresh --force 9 %%junk%% </dev/null || exit 1
python3 "$CH" elf /usr/bin/curl || { echo "  (curl not ELF after re-run)" >&2; exit 1; }
PORT=8876
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory /app/origin >/tmp/h2.log 2>&1 &
M=$!
for _ in $(seq 1 20); do
  sleep 0.3
  python3 -c "import socket,sys
try:
  s=socket.socket(); s.settimeout(.4); s.connect(('127.0.0.1',$PORT)); s.close(); sys.exit(0)
except: sys.exit(1)" && break
done
/usr/bin/curl -fsS "http://127.0.0.1:$PORT/basalt-bridge.html" -o /tmp/h2.out
rc=$?
kill "$M" 2>/dev/null || true
if [ "$rc" = 0 ] && cmp -s /tmp/h2.out /app/origin/basalt-bridge.html; then
  echo "  (restore re-run idempotent; curl still real and fetching)"
  exit 0
fi
echo "  (restore re-run broke or curl not fetching)" >&2
exit 1