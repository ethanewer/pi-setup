#!/bin/bash
# larch-hearth oracle (solution/solve.sh).
#
# A REAL solution: writes the driver /app/run.sh and the main scenario
# /app/scenario-main.json, then RUNS the driver (no precomputed artifact, never
# reads /tests) so it produces /app/guest.iso, /app/serial.log, /app/guest.prog.exit
# and the copied CD artifacts by actually booting the emulated guest.
set -euo pipefail

cat > /app/scenario-main.json <<'JEND'
{
  "name": "main",
  "exit_status": 21,
  "payload": "LARCH-HEARTH-MAIN-77",
  "login_user": "root",
  "serial_port": 55691
}
JEND

cat > /app/run.sh <<'REND'
#!/bin/bash
# /app/run.sh — larch-hearth driver.
#
# For a scenario JSON it: (re)assembles a tool CD (guest.iso), injects a custom
# init into a copy of /app/base-initrd.cpio.gz (cdrom mount + 9p host root +
# in-guest static asm compile/run + no-password serial login), boots the tiny
# guest under QEMU TCG, drives the serial console to a login, captures
# serial.log, copies the guest's host-fs writes into OUTDIR, and leaves qemu up.
#
# Usage: /app/run.sh [SCENARIO_JSON] [OUTDIR]
set -u

SCN="${1:-/app/scenario-main.json}"
OUT="${2:-/app}"

getc() { python3 -c "import json,sys;print(json.load(open('$SCN')).get('$1',''))"; }
NAME=$(getc name); [ -n "$NAME" ] || NAME=main
ES=$(getc exit_status)
PAY=$(getc payload)
LU=$(getc login_user); [ -n "$LU" ] || LU=root
SP=$(getc serial_port)

if [ -z "$ES" ] || [ -z "$PAY" ] || [ -z "$SP" ]; then
  echo "larch run.sh: bad scenario file $SCN" >&2
  exit 2
fi

# ---- clean stale qemu, reset shared work area -----------------------------
pkill -f qemu-system-x86_64 2>/dev/null
sleep 1
mkdir -p /opt/larch/work
rm -rf /opt/larch/work/*
mkdir -p "$OUT"

# ---- host-side in-guest driver: compile a static inline-asm program ----
# Guest_work.sh runs chrooted into the 9p-shared host root; it COMPILES a tiny
# statically-linked freestanding program (inline asm sets the exit status via
# the exit syscall) with the container toolchain. The program is kept tiny so
# its 9p write is byte-exact; the init copies it to the guest's RAM initramfs
# and runs it there for determinism.
cat > /opt/larch/guest_work.sh <<'GW'
#!/bin/bash
set -u
cd /opt/larch || exit 9
ES="$1"
cat > prog.c <<P
__attribute__((naked,noreturn)) void _start(void){
  asm volatile(
    "movl \$$ES,%edi\n\t"
    "movl \$60,%eax\n\t"
    "syscall");
}
P
gcc -nostdlib -static -O1 -o prog prog.c && echo "LARCH_COMPILE_OK"
GW
chmod +x /opt/larch/guest_work.sh

# ---- assemble the tool CD (guest.iso) --------------------------------------
TREE=/opt/larch/isotree
rm -rf "$TREE"; mkdir -p "$TREE/toolkit"
cat > "$TREE/toolkit/gadget.sh" <<'GADGET'
#!/bin/sh
echo "TOOL_RAN_OK"
echo "CD_MANIFEST=$(cat /cd/toolkit/manifest.txt)"
GADGET
chmod +x "$TREE/toolkit/gadget.sh"
printf '%s\n' "$PAY" > "$TREE/toolkit/manifest.txt"
xorriso -as mkisofs -quiet -o "$OUT/guest.iso" "$TREE"

# ---- inject a custom init into a copy of the base initramfs ---------------
INJ=/opt/larch/inj
rm -rf "$INJ"; mkdir -p "$INJ"
( cd "$INJ" && gzip -dc /app/base-initrd.cpio.gz | cpio -idm --quiet )
cat > "$INJ/etc/passwd" <<PASS
root::0:0:root:/root:/bin/sh
$LU::1000:1000:$LU:/home/$LU:/bin/sh
PASS
cat > "$INJ/etc/group" <<GRP
root:x:0:
$LU:x:1000:
GRP
cat > "$INJ/init" <<'IN'
#!/bin/sh
mount -t proc proc /proc 2>/dev/null
mount -t sysfs sysfs /sys 2>/dev/null
mount -t devtmpfs devtmpfs /dev 2>/dev/null
CMDLINE=$(cat /proc/cmdline)
ES=$(echo "$CMDLINE" | sed -n 's/.*larch_es=\([0-9][0-9]*\).*/\1/p')
echo "LARCH_BOOT_OK"
insmod /lib/modules/fs/isofs/isofs.ko 2>/dev/null
mkdir -p /cd
if mount -t iso9660 -o ro /dev/sr0 /cd 2>/dev/null; then
  echo "LARCH_CDROM_MOUNT_OK"
  /bin/sh /cd/toolkit/gadget.sh
else
  echo "LARCH_CDROM_MOUNT_FAIL"
fi
insmod /lib/modules/net/9p/9pnet.ko 2>/dev/null
insmod /lib/modules/net/9p/9pnet_virtio.ko 2>/dev/null
insmod /lib/modules/fs/netfs/netfs.ko 2>/dev/null
insmod /lib/modules/fs/9p/9p.ko 2>/dev/null
if mount -t 9p -o trans=virtio,version=9p2000.L hostroot /hr 2>/dev/null; then
  echo "LARCH_HOSTROOT_MOUNT_OK"
  mkdir -p /hr/opt/larch/work
  cp /cd/toolkit/gadget.sh /hr/opt/larch/work/gadget.sh 2>/dev/null
  cp /cd/toolkit/manifest.txt /hr/opt/larch/work/cdmanifest 2>/dev/null
  echo "LARCH_CDTOOL_COPIED"
  if [ -x /hr/opt/larch/guest_work.sh ]; then
    chroot /hr /bin/bash /opt/larch/guest_work.sh "$ES"
    echo "LARCH_GUEST_WORK_RETURNED"
  else
    echo "LARCH_NO_WORK_SCRIPT"
  fi
  cp /hr/opt/larch/prog /prog 2>/dev/null
  /prog; PE=$?
  echo "ASM_EXIT_STATUS=$PE"
  echo "$PE" > /hr/opt/larch/work/guest.prog.exit 2>/dev/null
else
  echo "LARCH_HOSTROOT_MOUNT_FAIL"
fi
echo "LARCH_READY_FOR_LOGIN"
exec setsid cttyhack /bin/login
IN
chmod +x "$INJ/init"
( cd "$INJ" && find . | cpio -o -H newc 2>/dev/null | gzip -9 > /opt/larch/initrd.cpio.gz )

# ---- boot the tiny guest in the background --------------------------------
nohup qemu-system-x86_64 -machine pc -m 768 -smp 1 -accel tcg \
  -kernel /app/vmlinuz -initrd /opt/larch/initrd.cpio.gz \
  -append "console=ttyS0 panic=-1 rdinit=/init larch_es=$ES" \
  -nographic -no-reboot \
  -cdrom "$OUT/guest.iso" \
  -virtfs local,path=/,mount_tag=hostroot,security_model=none \
  -serial tcp:127.0.0.1:$SP,server,nowait \
  > /opt/larch/qemu.log 2>&1 &
QP=$!

# ---- drive the serial console to a no-password login ----------------------
python3 - "$SP" "$LU" "$OUT" <<'PY'
import socket, sys, time
port, user, out = int(sys.argv[1]), sys.argv[2], sys.argv[3]
s = None
for _ in range(240):
    try:
        s = socket.create_connection(("127.0.0.1", port), 2); break
    except Exception:
        time.sleep(0.5)
if s is None:
    open(out + "/serial.log", "wb").write(b"NO_CONNECT\n"); sys.exit(1)
buf = b""
def has(xs):
    t = buf.decode(errors="ignore")
    return any(x in t for x in xs)
def drain(t):
    global buf
    end = time.time() + t
    while time.time() < end:
        try:
            d = s.recv(8192)
            if not d: break
            buf += d
        except Exception:
            time.sleep(0.05)
def send(x):
    try: s.sendall(x)
    except Exception: pass
try:
    waited = 0
    while waited < 120 and not has(["login:", "LARCH_BOOT_OK"]):
        drain(0.5); waited += 1
    # wait until the login prompt is actually up (work already finished)
    clock = 0
    while clock < 120 and not has(["login:"]):
        drain(0.5); clock += 1
    send((user + "\n").encode())
    clock = 0
    while clock < 60 and not has(["#", "$"]):
        drain(0.5); clock += 1
    send(b"echo LARCH_AUTH_OK\n")
    clock = 0
    while clock < 30 and not has(["LARCH_AUTH_OK"]):
        drain(0.5); clock += 1
    time.sleep(0.5)
    drain(1.0)
finally:
    try: s.close()
    except Exception: pass
    open(out + "/serial.log", "wb").write(buf)
PY

# ---- copy the guest's host-fs writes into OUTDIR --------------------------
cp -f /opt/larch/work/guest.prog.exit "$OUT/guest.prog.exit" 2>/dev/null
cp -f /opt/larch/work/cdmanifest "$OUT/cdmanifest" 2>/dev/null
cp -f /opt/larch/work/gadget.sh "$OUT/gadget.sh" 2>/dev/null

sleep 1
if kill -0 "$QP" 2>/dev/null; then ALIVE=1; else ALIVE=0; fi
echo "larch run.sh: scenario=$NAME exit_status=$ES qemu_alive=$ALIVE"
exit 0

REND
chmod +x /app/run.sh

echo "larch solve: running driver for main scenario"
cd /app && bash /app/run.sh
echo "larch solve: done; deliverables in /app:"
ls -la /app/guest.iso /app/serial.log /app/guest.prog.exit 2>/dev/null || true
