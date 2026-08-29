#!/bin/bash
# brisk-jetty run_guest.sh — the Nysa relay appliance bring-up driver.
#
# Binds the scenario together: boots the distro-less busybox+dropbear guest OS
# (/opt/gk/guest-initrd.cpio.gz, provisioned by the supplied /opt/gk/mkguest.sh
# fixture) under QEMU software emulation (TCG, no /dev/kvm), attaches the guest
# to /app/guest.qcow2, forwards two host loopback ports into the guest
# (127.0.0.1:61234 -> guest sshd:22 and 127.0.0.1:18080 -> guest relay:3733),
# and — because the guest boots UNENROLLED to a serial login console — drives
# that console non-interactively (typed root login, set hostname, run `enroll`)
# until the appliance reports NYSA-READY. The emulator is daemonized so it keeps
# running after this script exits.
#
# The full serial transcript (boot + the typed first-run configuration steps) is
# captured to /app/guest_console.log, and the emulator PID to
# /app/guest_daemon.pid.
#
# Usage:
#   bash /app/run_guest.sh             ensure the guest is up (idempotent)
#   bash /app/run_guest.sh STATUS      exit 0 iff the ssh forward is reachable
#   bash /app/run_guest.sh STOP        tear the guest down
set -u

APP=/app
SSH_PORT="${NYSA_SSH_PORT:-61234}"
RELAY_PORT="${NYSA_RELAY_PORT:-18080}"
GUEST_PORT=22
RELAY_GUEST_PORT=3733
PASSWORD="${NYSA_ROOT_PASSWORD:-kestrel-mistral-1987}"
HOSTNAME="${NYSA_GUEST_HOSTNAME:-nysa-relay-appliance}"

KERNEL=/opt/gk/vmlinuz
INITRD=/opt/gk/guest-initrd.cpio.gz
SOCK=/tmp/nysa-console.sock
LOG="$APP/guest_console.log"
PIDFILE="$APP/guest_daemon.pid"
QCOW="$APP/guest.qcow2"

log() { echo "[nysa] $*"; }

proc_alive() {
  [ -f "$PIDFILE" ] || return 1
  pid=$(cat "$PIDFILE" 2>/dev/null) || return 1
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

port_open() {
  python3 -c "import socket,sys
try:
    s=socket.socket(); s.settimeout(1.0); s.connect(('127.0.0.1',$SSH_PORT)); s.close(); sys.exit(0)
except Exception: sys.exit(1)"
}

ssh_banner_ok() {
  python3 - "$SSH_PORT" <<'PY'
import socket, sys, time
p = int(sys.argv[1])
try:
    s = socket.socket(); s.settimeout(3.0)
    s.connect(('127.0.0.1', p)); s.sendall(b'\r\n')
    buf = b''; end = time.time() + 2.5
    while time.time() < end:
        c = s.recv(256)
        if not c: break
        buf += c
        if b'SSH-2.0' in buf or len(buf) > 64: break
    s.close()
    sys.exit(0 if b'SSH-2.0' in buf else 1)
except Exception:
    sys.exit(1)
PY
}

already_up() { proc_alive && port_open; }

cmd="${1:-run}"
case "$cmd" in
  STATUS|status|--status)
    if already_up; then log "guest up (pid=$(cat "$PIDFILE" 2>/dev/null))"; exit 0; fi
    log "guest NOT reachable"; exit 1 ;;
  STOP|stop|--stop)
    pid=$(cat "$PIDFILE" 2>/dev/null || true)
    [ -n "${pid:-}" ] && kill -9 "$pid" 2>/dev/null || true
    rm -f "$PIDFILE" "$SOCK"
    log "stopped"; exit 0 ;;
  run|--ensure|-x|"")
    : ;;
  *)
    echo "usage: run_guest.sh [run|STATUS|STOP]" >&2; exit 2 ;;
esac

# ---- idempotency: if the forwarded guest is already up, do nothing ------------
if already_up; then
  log "already up (pid=$(cat "$PIDFILE" 2>/dev/null))"
  exit 0
fi
# A stale qemu from a previous crashed run must not linger.
if proc_alive; then
  pid=$(cat "$PIDFILE"); kill -9 "$pid" 2>/dev/null || true; rm -f "$PIDFILE"
fi

mkdir -p "$APP"

# ---- create the guest scratch disk -------------------------------------------
rm -f "$QCOW"
qemu-img create -f qcow2 "$QCOW" 64M >/dev/null

# ---- launch the emulator daemonized, serial on a unix socket + captured ------
rm -f "$SOCK" "$LOG"
qemu-system-x86_64 -machine pc,accel=tcg -m 512 -smp 1 -display none \
  -kernel "$KERNEL" -initrd "$INITRD" \
  -append "console=ttyS0 rdinit=/init panic=-1 nokaslr quiet" \
  -drive file="$QCOW",format=qcow2,if=ide,media=disk \
  -netdev user,id=n0,hostfwd=tcp:127.0.0.1:${SSH_PORT}-:${GUEST_PORT},hostfwd=tcp:127.0.0.1:${RELAY_PORT}-:${RELAY_GUEST_PORT} \
  -device virtio-net-pci,netdev=n0 \
  -chardev socket,id=nysa0,path="$SOCK",server=on,wait=off,logfile="$LOG" \
  -serial chardev:nysa0 \
  -pidfile "$PIDFILE" \
  -daemonize 2>>"$APP/qemu.err" || { log "qemu failed to start"; exit 1; }

# ---- drive the guest's first-run serial console non-interactively ------------
log "booting guest and driving the serial console..."
python3 - "$SOCK" "$PASSWORD" "$HOSTNAME" <<'PYDRIVE'
import socket, sys, time, select

SOCK, PASSWORD, HOSTNAME = sys.argv[1], sys.argv[2], sys.argv[3]

def connect(path, tries=200, delay=0.1):
    last = None
    for _ in range(tries):
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.connect(path); s.settimeout(1.0)
            return s
        except Exception as e:
            last = e; time.sleep(delay)
    raise SystemExit('nysa: cannot connect to serial socket: %r' % last)

def expect(s, needles, timeout, buf=b''):
    deadline = time.time() + timeout
    while time.time() < deadline:
        for n in needles:
            if n in buf:
                return n, buf
        r, _, _ = select.select([s], [], [], 0.25)
        if r:
            try:
                d = s.recv(16384)
            except socket.timeout:
                continue
            if not d:
                time.sleep(0.2); continue
            buf += d
    return None, buf

def send(s, text):
    s.sendall(text.encode()); time.sleep(0.5)

def step(s, step, buf):
    print('[nysa-drive] %s' % step, flush=True)
    return buf

s = connect(SOCK)
buf = b''
m, buf = expect(s, [b'login:'], timeout=150);   buf = step(s, 'waiting for login prompt' if m else 'MISS login prompt', buf)
if not m: sys.exit(1)
send(s, 'root\n')
m, buf = expect(s, [b'Password:'], timeout=30, buf=buf); buf = step(s, 'password prompt' if m else 'MISS password prompt', buf)
if not m: sys.exit(1)
send(s, PASSWORD + '\n')
m, buf = expect(s, [b'#'], timeout=30, buf=buf);       buf = step(s, 'root shell prompt' if m else 'MISS shell prompt', buf)
if not m: sys.exit(1)
# interactive OS-first configuration steps
send(s, 'hostname %s\n' % HOSTNAME)
send(s, 'echo %s > /etc/hostname\n' % HOSTNAME)
buf = step(s, 'hostname set', buf)
send(s, 'enroll\n')
m, buf = expect(s, [b'NYSA-READY'], timeout=60, buf=buf); buf = step(s, 'NYSA-READY' if m else 'MISS NYSA-READY', buf)
s.close()
sys.exit(0 if m else 1)
PYDRIVE
DRIVE_RC=$?

# ---- wait for the forwarded ssh to come up and record restart status ----------
fwd_ok=0
for _ in $(seq 1 40); do
  if ssh_banner_ok; then fwd_ok=1; break; fi
  sleep 1
done

if ! proc_alive; then
  log "guest daemon died"; exit 1
fi

if [ "$DRIVE_RC" = 0 ] && [ "$fwd_ok" = 1 ]; then
  log "guest ready: ssh forwarded on $SSH_PORT, relay on $RELAY_PORT (pid=$(cat "$PIDFILE"))"
  exit 0
fi
log "console drive rc=$DRIVE_RC fwd=$fwd_ok — guest did not reach ready state" >&2
exit 1
