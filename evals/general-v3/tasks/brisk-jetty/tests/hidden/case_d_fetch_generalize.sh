#!/bin/bash
# Hidden case D — fetch.py generalization.
# fetch.py must fetch ANY reachable URL (not just the canned /live page) and
# write exactly the bytes served. A verifier-local loopback HTTP server serves a
# fresh, different page.
set -u
D=/tmp/nysa_case_d
rm -rf "$D"; mkdir -p "$D"
printf 'NYSA-CASE-D-<unusual> payload: reef-%-06d\n' "$RANDOM" > "$D/other.txt"

PORT=18777
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$D" >/tmp/case_d_srv.log 2>&1 &
SRV=$!
for _ in $(seq 1 30); do
  python3 -c "
import socket
try:
    s=socket.socket(); s.settimeout(.3); s.connect(('127.0.0.1',$PORT)); s.close(); raise SystemExit(0)
except Exception: raise SystemExit(1)" && break
  sleep 0.2
done

python3 /app/fetch.py http://127.0.0.1:$PORT/other.txt /tmp/nysa_case_d_out.bin >/tmp/case_d.log 2>&1
rc=$?
kill "$SRV" 2>/dev/null || true
[ "$rc" -eq 0 ] || { echo "case_d: fetch.py failed on a live URL (rc=$rc)" >&2; exit 1; }
cmp -s /tmp/nysa_case_d_out.bin "$D/other.txt" \
  || { echo "case_d: fetched bytes differ from served bytes" >&2; exit 1; }
exit 0
