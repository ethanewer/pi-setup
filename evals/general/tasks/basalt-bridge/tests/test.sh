#!/usr/bin/env bash
# basalt-bridge verifier. Runs after the solver finishes; the daemonized guest and
# the restored curl are live in this container. Executes the deliverables and hidden
# scenarios, then writes 0/1 to /logs/verifier/reward.txt.
# A pristine (unsolved) container must end with reward 0.
set -uo pipefail

LOGS=/logs/verifier
mkdir -p "$LOGS"
reward=0

CH=/tests/checks.py
FW=${1:-3134}           # host loopback port forwarded into the guest sshd
VMIRROR=8791            # verifier-local loopback mirror of the true remote bytes

echo "[basalt] starting verifier"
fail() { echo "[basalt] FAIL: $*" >&2; echo "0" > "$LOGS/reward.txt"; exit 0; }

# ---- 0) all deliveries present ------------------------------------------------
for f in /app/run_guest.sh /app/restore_curl.sh /app/guest.qcow2 \
         /app/forward_check.log /app/guest_daemon.pid /app/fetch_result.html; do
  [ -f "$f" ] || fail "missing delivery $f"
done

# ---- 1) host -> guest reach via the forwarded host port ----------------------
if python3 "$CH" banner "$FW"; then
  echo "[verify] forwarded host port $FW reaches guest sshd"
else
  fail "forwarded host port $FW does not reach guest sshd"
fi

# ---- 2) guest daemon pid is alive and is the forwarded qemu ------------------
PID=$(cat /app/guest_daemon.pid 2>/dev/null || true)
python3 "$CH" alive "${PID:-0}" || fail "guest daemon pid=${PID:-?} not alive"
if ! tr '\0' ' ' < "/proc/$PID/cmdline" 2>/dev/null | grep -q "hostfwd=tcp:127.0.0.1:$FW-:22"; then
  fail "pid=$PID is not the qemu with the forwarding config"
fi
echo "[verify] guest daemon pid=$PID alive and forwards port $FW"

# ---- 3) forward_check.log recorded a real probe -------------------------------
grep -q 'status=OPEN' /app/forward_check.log || fail "forward_check.log lacks status=OPEN"
grep -q 'SSH-2.0' /app/forward_check.log || fail "forward_check.log lacks ssh banner"
echo "[verify] forward_check.log records an OPEN ssh probe"

# ---- 4) guest.qcow2 is a valid qcow2 disk -------------------------------------
python3 "$CH" qcow /app/guest.qcow2 || fail "/app/guest.qcow2 is not a valid qcow2"
echo "[verify] /app/guest.qcow2 is a valid qcow2"

# ---- 5) curl is a genuine executable -------------------------------------------
python3 "$CH" elf /usr/bin/curl || fail "/usr/bin/curl is not a genuine ELF executable"
/usr/bin/curl --version 2>/dev/null | grep -qi curl || fail "/usr/bin/curl reports no identity"
echo "[verify] /usr/bin/curl is a genuine executable curl"

# ---- 6) fetch_result.html == true remote content -------------------------------
cmp -s /app/fetch_result.html /app/origin/basalt-bridge.html \
  || fail "/app/fetch_result.html != true remote bytes"
echo "[verify] /app/fetch_result.html equals true remote content"

# ---- 7) a live loopback fetch returns the same true remote ---------------------
python3 -m http.server "$VMIRROR" --bind 127.0.0.1 --directory /app/origin \
    >/tmp/origin.log 2>&1 &
MIR=$!
for _ in $(seq 1 20); do
  sleep 0.3
  python3 -c "import socket,sys
try:
  s=socket.socket(); s.settimeout(.4); s.connect(('127.0.0.1',$VMIRROR)); s.close(); sys.exit(0)
except Exception: sys.exit(1)" && break
done
if python3 "$CH" http_ok "$VMIRROR" /basalt-bridge.html /app/origin/basalt-bridge.html; then
  echo "[verify] live loopback fetch returns the true remote content"
else
  kill "$MIR" 2>/dev/null || true
  fail "live loopback fetch did not return the true remote content"
fi
kill "$MIR" 2>/dev/null || true

# ---- 8) hidden cases ------------------------------------------------------------
all_ok=1
for c in /tests/hidden/*.sh; do
  [ -f "$c" ] || continue
  if bash "$c" "$FW" "$CH"; then
    echo "[verify] hidden OK: $(basename "$c")"
  else
    echo "[verify] FAIL hidden: $(basename "$c")" >&2
    all_ok=0
  fi
done

[ "$all_ok" = 1 ] && reward=1
echo "[verify] result REWARD=$reward"
echo "$reward" > "$LOGS/reward.txt"
exit 0