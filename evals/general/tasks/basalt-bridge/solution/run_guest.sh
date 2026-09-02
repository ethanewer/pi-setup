#!/bin/bash
# basalt-bridge run_guest.sh
#
# Boots a tiny busybox Linux guest in headless QEMU software emulation (TCG, no
# /dev/kvm), forwards a host loopback port into the guest sshd (dropbear) via QEMU
# user-mode networking, and keeps the emulator running as a daemonized background
# process (qemu -daemonize -pidfile) that survives this script exiting.
#
# Usage:
#   bash /app/run_guest.sh                 ensure the guest is up (idempotent)
#   bash /app/run_guest.sh STATUS          print state; exit 0 iff forwarded-reachable
#   bash /app/run_guest.sh STOP            tear the guest down
#
# On success it records the daemon PID to /app/guest_daemon.pid and a host->guest
# reachability probe (the live sshd banner) to /app/forward_check.log.
set -u

APP=/app
FORWARD_PORT="${BASALT_FORWARD_PORT:-3134}"
KERNEL=/opt/gk/vmlinuz
BUSYBOX=/opt/gk/busybox
MODDIR=/opt/gk/modules
DROPBEAR=$(command -v dropbear)
DROPBEARKEY=$(command -v dropbearkey)

GUEST_QCOW="$APP/guest.qcow2"
PIDFILE="$APP/guest_daemon.pid"
SERIAL_LOG=/tmp/basalt-bridge-serial.log
READY_MARKER="BASALT-BRIDGE-READY"

log() { printf '[basalt] %s\n' "$*"; }

proc_alive() {
  [ -f "$PIDFILE" ] || return 1
  pid=$(cat "$PIDFILE" 2>/dev/null)
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

port_open() {
  [ -f "$PIDFILE" ] || return 1
  python3 -c "import socket,sys; s=socket.socket(); s.settimeout(1.0)
try:
  s.connect(('127.0.0.1',$FORWARD_PORT)); s.close(); sys.exit(0)
except Exception: sys.exit(1)"
}

already_up() { proc_alive && port_open; }

# Probe the forwarded host port and print the guest sshd banner.
# Exits 0 iff it reads a real SSH banner.
probe_banner() {
  python3 -c "import socket,sys,time
p=$FORWARD_PORT; s=socket.socket(); s.settimeout(3.0)
buf=b''
try:
  s.connect(('127.0.0.1',p)); s.sendall(b'\r\n')
  end=time.time()+2.5
  while time.time()<end:
    c=s.recv(256)
    if not c: break
    buf+=c
    if b'SSH-2.0-' in buf or len(buf)>64: break
  s.close()
  line=buf.decode('utf-8','replace').splitlines()
  print(line[0] if line else buf.decode(errors='replace')[:64])
  sys.exit(0 if 'SSH-2.0' in buf.decode('ascii','replace') else 1)
except Exception:
  sys.exit(1)"
}

cmd="${1:-run}"
if [ "$cmd" = "STATUS" ] || [ "$cmd" = "--status" ]; then
  if already_up; then
    echo "basalt-bridge: guest is running (pid=$(cat "$PIDFILE"))"; exit 0
  else
    echo "basalt-bridge: guest is NOT running"; exit 1
  fi
fi
if [ "$cmd" = "STOP" ] || [ "$cmd" = "--stop" ]; then
  pid=$(cat "$PIDFILE" 2>/dev/null || true)
  [ -n "${pid:-}" ] && kill -9 "$pid" 2>/dev/null || true
  rm -f "$PIDFILE"
  echo "basalt-bridge: stopped"; exit 0
fi

# ---- idempotency: already up means we do nothing -----------------------------
if already_up; then
  echo "basalt-bridge: guest already up (pid=$(cat "$PIDFILE"))"; exit 0
fi

mkdir -p "$APP"

# ---- create the guest disk image (scratch workspace for the running VM) ------
rm -f "$GUEST_QCOW"
qemu-img create -f qcow2 "$GUEST_QCOW" 64M >/dev/null

# ---- assemble the guest initramfs --------------------------------------------
ROOT=$(mktemp -d)
mkdir -p "$ROOT/bin" "$ROOT/sbin" "$ROOT/etc/dropbear" "$ROOT/dev" \
         "$ROOT/proc" "$ROOT/sys" "$ROOT/run" "$ROOT/var/run" \
         "$ROOT/lib/x86_64-linux-gnu" "$ROOT/usr/lib/x86_64-linux-gnu" \
         "$ROOT/lib64" "$ROOT/modules"
cp -L "$BUSYBOX" "$ROOT/bin/busybox"
( cd "$ROOT/bin" && ./busybox --list 2>/dev/null | while read a; do
    [ "$a" != busybox ] && ln -sf busybox "$a"
  done )
cp -L "$DROPBEAR" "$ROOT/sbin/dropbear"
for l in $(ldd "$DROPBEAR" | awk '{print $3}' | grep '^/'); do
  b=$(basename "$l")
  cp -L "$l" "$ROOT/lib/x86_64-linux-gnu/$b" 2>/dev/null || true
  cp -L "$l" "$ROOT/usr/lib/x86_64-linux-gnu/$b" 2>/dev/null || true
done
[ -f /lib64/ld-linux-x86-64.so.2 ] && cp -L /lib64/ld-linux-x86-64.so.2 "$ROOT/lib64/"
[ -f /lib/x86_64-linux-gnu/ld-linux-x86-64.so.2 ] && cp -L /lib/x86_64-linux-gnu/ld-linux-x86-64.so.2 "$ROOT/lib/x86_64-linux-gnu/"
"$DROPBEARKEY" -t rsa -f "$ROOT/etc/dropbear/dropbear_rsa_host_key" -s 2048 >/dev/null 2>&1
printf 'BASALT-BRIDGE host\n' > "$ROOT/etc/hostname"
printf '127.0.0.1 localhost\n' > "$ROOT/etc/hosts"
printf 'root:x:0:0:root:/root:/bin/sh\n' > "$ROOT/etc/passwd"
cp -f "$MODDIR"/*.ko "$ROOT/modules/" 2>/dev/null

cat > "$ROOT/init" <<'INIT'
#!/bin/sh
export PATH=/bin:/sbin
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev 2>/dev/null
mkdir -p /dev/pts /run /var/run
mount -t devpts none /dev/pts 2>/dev/null
echo "BASALT-BRIDGE boot $(cat /etc/hostname 2>/dev/null)"
# load guest NIC drivers (tolerate modules that are already built-in)
for m in virtio virtio_ring virtio_pci virtio_net; do
  [ -f "/modules/$m.ko" ] && insmod "/modules/$m.ko" 2>/dev/null
done
for i in 1 2 3 4 5; do
  if ifconfig eth0 10.0.2.15 netmask 255.255.255.0 up 2>/dev/null; then break; fi
  sleep 1
done
route add default gw 10.0.2.2 2>/dev/null
/sbin/dropbear -p 22 -r /etc/dropbear/dropbear_rsa_host_key >/dev/null 2>&1 &
echo "BASALT-BRIDGE-READY"
while true; do sleep 3600; done
INIT
chmod +x "$ROOT/init"
( cd "$ROOT" && find . | cpio -o -H newc 2>/dev/null | gzip -9 > /tmp/basalt-initrd.gz )
rm -rf "$ROOT"

# ---- boot the guest daemonized under software emulation ------------------------
rm -f "$SERIAL_LOG" "$PIDFILE"
qemu-system-x86_64 -machine pc,accel=tcg -m 512 -smp 1 -display none \
  -kernel "$KERNEL" -initrd /tmp/basalt-initrd.gz \
  -append "console=ttyS0 rdinit=/init panic=-1 nokaslr quiet" \
  -drive file="$GUEST_QCOW",format=qcow2,if=ide,media=disk \
  -netdev user,id=n0,hostfwd=tcp:127.0.0.1:$FORWARD_PORT-:22 \
  -device virtio-net-pci,netdev=n0 \
  -serial file:"$SERIAL_LOG" \
  -pidfile "$PIDFILE" \
  -daemonize 2>>/tmp/basalt-qemu.err

# ---- wait for the guest to come up, then probe host->guest sshd --------------
ready=0
for i in $(seq 1 90); do
  if grep -q "$READY_MARKER" "$SERIAL_LOG" 2>/dev/null; then ready=1; break; fi
  sleep 1
done
sleep 1

fwd_ok=0; banner=""
if [ "$ready" = 1 ]; then
  for i in $(seq 1 30); do
    banner=$(probe_banner 2>/dev/null || true)
    if printf '%s' "$banner" | grep -q 'SSH-2.0'; then fwd_ok=1; break; fi
    sleep 1
  done
fi

printf 'basalt-forward-port=%s\n' "$FORWARD_PORT" > "$APP/forward_check.log"
if [ "$fwd_ok" = 1 ]; then
  printf 'status=OPEN\nbanner=%s\n' "$banner" >> "$APP/forward_check.log"
  echo "basalt-bridge: FORWARD OK ($banner)"
else
  printf 'status=UNREACHABLE\n' >> "$APP/forward_check.log"
  echo "basalt-bridge: FORWARD UNREACHABLE" >&2
fi

if proc_alive && [ "$fwd_ok" = 1 ]; then
  echo "basalt-bridge: guest up and reachable pid=$(cat "$PIDFILE")"
  exit 0
else
  exit 1
fi