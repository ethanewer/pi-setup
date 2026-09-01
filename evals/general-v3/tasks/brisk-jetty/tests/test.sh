#!/usr/bin/env bash
# brisk-jetty verifier (tests/test.sh)
#
# Runs after the agent finishes while the daemonized guest is still alive and
# /etc/hosts has been repaired. Independently of how the agent implemented it,
# this verifier EXECUTES the deliverables and checks behaviour:
#   * the emulated guest is reachable via ssh on the forwarded host port;
#   * the serial-console log shows the interactive first-run steps were typed;
#   * the relay panel is reachable on the second forwarded host port;
#   * ssh_host_exec.sh genuinely runs arbitrary remote commands;
#   * the host network path was repaired (nysa.test -> 127.0.0.1) and
#     /app/fetch_result.html holds the LIVE page the guest serves right now;
#   * hidden cases confirm the deliverables generalize (dead-URL safe fetch,
#     ssh exec arg handling, idempotent bring-up, generalized fetch).
#
# A pristine (unsolved) container must end with reward 0.
set -uo pipefail

mkdir -p /logs/verifier
reward=0

SSH_PORT=61234
RELAY_PORT=18080
RELAY_HOST=nysa.test

fail() { echo "[verify] FAIL: $*" >&2; echo "0" > /logs/verifier/reward.txt; exit 0; }

banner_ok() { # port -> 0 iff an ssh banner is read on that forwarded port
  python3 - "$1" <<'PY'
import socket, sys, time
p = int(sys.argv[1])
try:
    s = socket.socket(); s.settimeout(4.0)
    s.connect(('127.0.0.1', p)); s.sendall(b'\r\n')
    buf = b''; end = time.time() + 3.0
    while time.time() < end:
        c = s.recv(256)
        if not c: break
        buf += c
        if b'SSH-2.0' in buf or len(buf) > 60: break
    s.close()
    sys.exit(0 if b'SSH-2.0' in buf else 1)
except Exception:
    sys.exit(1)
PY
}

http_get() { # port path -> body on stdout, exit 0 on success
  python3 - "$1" "$2" <<'PY'
import sys, urllib.request
try:
    b = urllib.request.urlopen('http://127.0.0.1:%d%s' % (int(sys.argv[1]), sys.argv[2]), timeout=6).read()
    sys.stdout.buffer.write(b); sys.exit(0)
except Exception:
    sys.exit(1)
PY
}

# ---- 0) all deliverables present ----------------------------------------------
for f in /app/guest.qcow2 /app/run_guest.sh /app/ssh_host_exec.sh /app/fetch.py \
         /app/fetch_result.html /app/guest_console.log /app/guest_daemon.pid; do
  [ -f "$f" ] || fail "missing deliverable $f"
done
[ -x /app/run_guest.sh ] || fail "/app/run_guest.sh not executable"
[ -x /app/ssh_host_exec.sh ] || fail "/app/ssh_host_exec.sh not executable"

# ---- 1) host -> guest reachable via the forwarded ssh port --------------------
banner_ok "$SSH_PORT" || fail "forwarded ssh port $SSH_PORT does not reach guest sshd"
echo "[verify] ssh banner on host port $SSH_PORT"

# ---- 2) the guest daemon is alive and is the qemu with both forwards ----------
PID=$(cat /app/guest_daemon.pid 2>/dev/null || echo 0)
kill -0 "$PID" 2>/dev/null || fail "guest daemon pid=$PID not alive"
CMDLINE=$(tr '\0' ' ' < "/proc/$PID/cmdline" 2>/dev/null)
echo "$CMDLINE" | grep -q 'qemu-system' || fail "pid $PID is not a qemu process"
echo "$CMDLINE" | grep -q "hostfwd=tcp:127.0.0.1:$SSH_PORT-:22" || fail "missing qemu ssh forward"
echo "$CMDLINE" | grep -q "hostfwd=tcp:127.0.0.1:$RELAY_PORT-:3733" || fail "missing qemu relay forward"
echo "$CMDLINE" | grep -q "/app/guest.qcow2" || fail "guest.qcow2 not attached to the running vm"
echo "[verify] guest daemon pid=$PID alive with both host forwards"

# ---- 3) the serial-console log shows the interactive first-run steps ----------
for pat in 'login:' 'Password:' 'hostname' 'enroll' 'NYSA-READY'; do
  grep -q "$pat" /app/guest_console.log || fail "console log lacks '$pat'"
done
grep -q 'nysa-relay-appliance' /app/guest_console.log || fail "console log lacks hostname step"
echo "[verify] console log records the interactive configuration steps"

# ---- 4) guest.qcow2 is a valid qcow2 ------------------------------------------
qemu-img info -U /app/guest.qcow2 2>/dev/null | grep -q qcow2 || fail "/app/guest.qcow2 is not valid qcow2"
echo "[verify] /app/guest.qcow2 is a valid qcow2 image"

# ---- 5) the relay panel is reachable on the forwarded relay port --------------
RELAY_BODY=$(http_get "$RELAY_PORT" /live) || fail "relay panel not reachable on port $RELAY_PORT"
echo "$RELAY_BODY" | grep -q 'RELAY-LIVE kestrel' || fail "relay /live lacks the RELAY-LIVE marker"
echo "[verify] relay panel serves the live marker on port $RELAY_PORT"

# ---- 6) host network path was repaired (nysa.test -> 127.0.0.1) ---------------
REPAIRED_IP=$(getent hosts "$RELAY_HOST" 2>/dev/null | awk '{print $1}' | head -1)
[ "$REPAIRED_IP" = "127.0.0.1" ] || fail "nysa.test does not resolve to 127.0.0.1 (got '$REPAIRED_IP')"
echo "[verify] repaired host resolution: $RELAY_HOST -> 127.0.0.1"

# ---- 7) ssh_host_exec.sh runs an arbitrary command in the guest ---------------
TOK_SSH=$(bash /app/ssh_host_exec.sh "awk '{print \$3}' /etc/rc/enroll" 2>/dev/null | sed 's/token=//' | tr -d '[:space:]')
[ -n "$TOK_SSH" ] || fail "ssh_host_exec.sh could not read /etc/rc/enroll"
echo "[verify] ssh_host_exec.sh reached the guest (token=$TOK_SSH)"

# ---- 8) fetch_result.html is the LIVE page matching a fresh live fetch --------
FRESH_FILE=$(mktemp)
http_get "$RELAY_PORT" /live > "$FRESH_FILE" || { rm -f "$FRESH_FILE"; fail "fresh live fetch failed"; }
[ -s "$FRESH_FILE" ] || { rm -f "$FRESH_FILE"; fail "fresh live fetch empty"; }
cmp -s /app/fetch_result.html "$FRESH_FILE" \
  || { rm -f "$FRESH_FILE"; fail "/app/fetch_result.html differs from the fresh live fetch"; }
grep -q "RELAY-LIVE kestrel $TOK_SSH" /app/fetch_result.html \
  || { rm -f "$FRESH_FILE"; fail "fetch_result.html does not carry the live token from the enrolled guest"; }
rm -f "$FRESH_FILE"
echo "[verify] fetch_result.html equals the fresh live relay page"

# ---- 9) the console log's enroll token matches the running service ------------
TOK_LOG=$(grep 'NYSA-READY token=' /app/guest_console.log | tail -1 | sed 's/.*token=\([0-9a-f]*\).*/\1/' | head -1)
[ -n "$TOK_LOG" ] && [ "$TOK_LOG" = "$TOK_SSH" ] \
  || fail "console-log token ($TOK_LOG) != service token ($TOK_SSH)"
echo "[verify] console-log enroll matches the live service"

# ---- 10) hidden cases -----------------------------------------------------------
all_ok=1
count=0
for c in /tests/hidden/*.sh; do
  [ -f "$c" ] || continue
  count=$((count + 1))
  if bash "$c"; then
    echo "[verify] hidden OK: $(basename "$c")"
  else
    echo "[verify] FAIL hidden: $(basename "$c")" >&2
    all_ok=0
  fi
done
[ "$count" -ge 2 ] || fail "expected >=2 hidden cases, found $count"

[ "$all_ok" = 1 ] && reward=1
echo "[verify] REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0
