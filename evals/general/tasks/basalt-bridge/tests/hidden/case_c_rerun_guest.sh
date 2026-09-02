#!/usr/bin/env bash
# Hidden case C: re-invoking run_guest.sh must be safe/idempotent (no duplicate
# emulator, no lost service) and the background guest must still answer on the
# forwarded host port afterwards, with the same daemon pid.
set -uo pipefail
FW="$1"; CH="$2"
OLD=$(cat /app/guest_daemon.pid 2>/dev/null || true)
before_count=$(pgrep -fc "hostfwd=tcp:127.0.0.1:$FW-:22" 2>/dev/null || echo 0)

out=$(bash /app/run_guest.sh 2>&1)
bash /app/run_guest.sh STATUS </dev/null >/tmp/h3.status 2>&1
sts=$?
after_count=$(pgrep -fc "hostfwd=tcp:127.0.0.1:$FW-:22" 2>/dev/null || echo 0)
NEWPID=$(cat /app/guest_daemon.pid 2>/dev/null || true)

if [ "$sts" -ne 0 ]; then echo "  (run_guest.sh STATUS failed)" >&2; exit 1; fi
if [ "$after_count" != "$before_count" ] || [ "$after_count" -lt 1 ]; then
  echo "  (re-run spawned a duplicate guest: before=$before_count after=$after_count)" >&2
  exit 1
fi
if [ -z "${NEWPID:-}" ] || [ "$NEWPID" != "$OLD" ]; then
  echo "  (guest daemon pid changed: old=$OLD new=${NEWPID:-none})" >&2
  exit 1
fi
python3 "$CH" banner "$FW" || { echo "  (forwarded port not reachable after re-run)" >&2; exit 1; }
python3 "$CH" alive "$NEWPID" || { echo "  (guest daemon gone)" >&2; exit 1; }
echo "  (run_guest.sh re-invocation safe; forward still reachable)"
exit 0