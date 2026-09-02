#!/bin/bash
# brisk-jetty oracle (solution/solve.sh)
#
# A REAL solution: installs the three driver deliverables into /app, then RUNS
# them for genuine effect —
#   1. run_guest.sh boots the guest under QEMU (TCG), drives its serial console
#      non-interactively through the first-run steps (root login, hostname,
#      `enroll`) and leaves the emulator daemonized with both host forwards;
#   2. ssh_host_exec.sh proves host->guest reachability by running a real
#      command inside the guest over the forwarded ssh port;
#   3. repairs host name resolution (append "127.0.0.1 nysa.test" to /etc/hosts);
#   4. fetch.py captures a genuine live fetch of the relay page over the repaired
#      path into /app/fetch_result.html.
# The emulator is left running; /etc/hosts stays repaired.
set -euo pipefail

SOL="$(dirname "$0")"

# --- deliverable scripts -------------------------------------------------------
install -m 0755 "$SOL/run_guest.sh" /app/run_guest.sh
install -m 0755 "$SOL/ssh_host_exec.sh" /app/ssh_host_exec.sh
install -m 0755 "$SOL/fetch.py" /app/fetch.py

# --- 1) boot + configure the guest via the simulation --------------------------
bash /app/run_guest.sh

# --- 2) prove reachability: run a real command in the guest over the forward ----
TOK="$(bash /app/ssh_host_exec.sh "awk '{print \$3}' /etc/rc/enroll" | sed 's/token=//')"
[ -n "$TOK" ] || { echo "solve: could not read enroll token via ssh" >&2; exit 1; }
echo "solve: ssh reachable, relay token=$TOK"

# --- 3) repair host name resolution for the relay appliance --------------------
python3 - <<'PY'
p = '/etc/hosts'
lines = [l for l in open(p) if 'nysa.test' not in l]
lines.append('127.0.0.1 nysa.test\n')
open(p, 'w').writelines(lines)
PY
getent hosts nysa.test >/dev/null || { echo "solve: nysa.test still unresolvable" >&2; exit 1; }
echo "solve: /etc/hosts repaired (nysa.test -> 127.0.0.1)"

# --- 4) genuine live fetch over the repaired path ------------------------------
python3 /app/fetch.py http://nysa.test:18080/live /app/fetch_result.html

# --- post-checks ----------------------------------------------------------------
[ -s /app/guest.qcow2 ] || { echo "solve: guest.qcow2 missing" >&2; exit 1; }
[ -s /app/guest_console.log ] || { echo "solve: guest_console.log missing" >&2; exit 1; }
grep -q 'NYSA-READY' /app/guest_console.log || { echo "solve: console log lacks NYSA-READY" >&2; exit 1; }
grep -q 'RELAY-LIVE kestrel' /app/fetch_result.html || { echo "solve: fetch_result.html lacks live marker" >&2; exit 1; }
kill -0 "$(cat /app/guest_daemon.pid)" || { echo "solve: guest daemon not alive" >&2; exit 1; }
echo "solve: OK (guest up, ssh reachable, live relay page captured)"
