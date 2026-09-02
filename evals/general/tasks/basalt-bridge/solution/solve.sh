#!/bin/bash
# basalt-bridge oracle: installs the deliverables and performs the REAL work — boot
# the guest (forwarded + daemonized), then repair curl and capture a live fetch.
set -euo pipefail

SOL="$(dirname "$0")"

# --- deliverable 1 & artifacts: guest.boot ------------------------------------
install -m 0755 "$SOL/run_guest.sh" /app/run_guest.sh
bash /app/run_guest.sh                # boots guest (daemonized) + qword + pidfile + probe

# sanity: the guest daemon must be alive now that our shell still runs
[ -f /app/guest_daemon.pid ] && kill -0 "$(cat /app/guest_daemon.pid)"

# --- deliverables: restore curl + live fetch ----------------------------------
install -m 0755 "$SOL/restore_curl.sh" /app/restore_curl.sh
bash /app/restore_curl.sh             # repairs /usr/bin/curl, serves mirror, fetches

# --- post-checks ---------------------------------------------------------------
[ -s /app/guest.qcow2 ] || { echo "solve: guest.qcow2 missing" >&2; exit 1; }
[ -s /app/forward_check.log ] || { echo "solve: forward_check.log missing" >&2; exit 1; }
[ -s /app/fetch_result.html ] || { echo "solve: fetch_result.html missing" >&2; exit 1; }
grep -q 'SSH-2.0' /app/forward_check.log || { echo "solve: no ssh banner recorded" >&2; exit 1; }
file /usr/bin/curl | grep -q ELF || { echo "solve: curl not restored to ELF" >&2; exit 1; }
echo "basalt-bridge solve: guest reachable, curl restored, fetch captured"
exit 0