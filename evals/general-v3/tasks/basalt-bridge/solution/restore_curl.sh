#!/bin/bash
# basalt-bridge restore_curl.sh
#
# Restores a bona fide executable curl onto the standard path and confirms the
# (repaired) loopback network path returns the true remote content.
#   - replaces /usr/bin/curl only when it is not a genuine native ELF executable
#   - ensures the loopback mirror (true remote bytes) is being served
#   - fetches the mirror with the restored curl into /app/fetch_result.html
#
# Safe to run repeatedly (idempotent); tolerates being handed stray arguments.
set -u

APP=/app
MIRROR_PORT="${BASALT_MIRROR_PORT:-8790}"
SRC=/opt/gk/curl.orig
URL="http://127.0.0.1:$MIRROR_PORT/basalt-bridge.html"

# ---- 1) repair /usr/bin/curl so it is a real native executable --------------
is_real() {
  python3 - <<'PY'
import os
p='/usr/bin/curl'
try:
    ok=os.access(p, os.X_OK|os.R_OK)
    b=open(p,'rb').read(4)
    ok=ok and b[:1]==b'\x7f' and b[1:]==b'ELF'
except Exception:
    ok=False
import sys; sys.exit(0 if ok else 1)
PY
}
if ! is_real; then
  cp -f "$SRC" /usr/bin/curl
fi
chmod 0755 /usr/bin/curl

# ---- 2) make sure the loopback mirror is serving the true remote bytes -------
mirror_up() {
  python3 -c "import socket,sys; s=socket.socket(); s.settimeout(1.0)
try: s.connect(('127.0.0.1',$MIRROR_PORT)); s.close(); sys.exit(0)
except Exception: sys.exit(1)"
}
if ! mirror_up; then
  ( cd "$APP/origin" && nohup python3 -m http.server "$MIRROR_PORT" --bind 127.0.0.1 \
       >/tmp/basalt-mirror.log 2>&1 & )
  for i in $(seq 1 20); do
    mirror_up && break
    sleep 0.3
  done
fi

# ---- 3) fetch the true remote content over the repaired path ------------------
if ! mirror_up; then echo "basalt: mirror unavailable" >&2; exit 1; fi
/usr/bin/curl -fsS "$URL" -o "$APP/fetch_result.html"
[ -s "$APP/fetch_result.html" ] || { echo "basalt: fetch empty" >&2; exit 1; }

echo "basalt: /usr/bin/curl restored ($(/usr/bin/curl --version | head -1))"
echo "basalt: fetch_result.html fetched ($(wc -c < "$APP/fetch_result.html") bytes)"
exit 0