#!/bin/bash
# Hidden case C — run_guest.sh idempotency.
# Re-running the bring-up while the guest is already up must NOT spawn a second
# emulator: the recorded daemon pid must stay the same, the number of qemu
# processes must not increase, and the forward must remain reachable.
set -u

P1=$(cat /app/guest_daemon.pid 2>/dev/null || echo 0)
NQ_BEFORE=$(pgrep -f 'qemu-system-x86_64' | wc -l)

bash /app/run_guest.sh >/tmp/case_c.log 2>&1
rc=$?
[ "$rc" -eq 0 ] || { echo "case_c: run_guest.sh re-run failed (rc=$rc)" >&2; exit 1; }

P2=$(cat /app/guest_daemon.pid 2>/dev/null || echo 0)
[ "$P1" = "$P2" ] || { echo "case_c: daemon pid drifted ($P1 -> $P2)" >&2; exit 1; }
kill -0 "$P2" 2>/dev/null || { echo "case_c: daemon $P2 not alive" >&2; exit 1; }

NQ_AFTER=$(pgrep -f 'qemu-system-x86_64' | wc -l)
[ "$NQ_AFTER" -le "$NQ_BEFORE" ] || { echo "case_c: qemu count grew ($NQ_BEFORE -> $NQ_AFTER)" >&2; exit 1; }

# ssh forward still reachable after the re-run
python3 - <<'PY'
import socket
try:
    s = socket.socket(); s.settimeout(4); s.connect(('127.0.0.1', 61234)); s.close()
    raise SystemExit(0)
except Exception:
    raise SystemExit(1)
PY
[ $? -eq 0 ] || { echo "case_c: ssh forward broke after re-run" >&2; exit 1; }

exit 0
