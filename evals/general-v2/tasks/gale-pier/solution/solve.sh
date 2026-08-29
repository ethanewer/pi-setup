#!/usr/bin/env bash
# Gale Pier bring-up oracle.
# Builds every deliverable by DOING the work, then RUNS the produced programs
# to generate the runtime artifacts. Never reads /tests.
set -euo pipefail
cd /app

# ---------------------------------------------------------------- kernel ----
cat > /app/build-kernel.sh <<'KSH'
#!/usr/bin/env bash
# build-kernel.sh -- compile the shipped Linux 6.8 source tree into a bootable
# x86_64 bzImage. Always rebuilds from the pristine distro tarball and copies
# the finished image to /app/kernel/bzImage.
set -euo pipefail

KSRC=/usr/src/linux-source-6.8.0.tar.bz2
OUT=/app/kernel/bzImage
WORK=/tmp/gale-kbuild

mkdir -p /app/kernel "$WORK"
cd "$WORK"
rm -rf linux-source-6.8.0

echo "[build-kernel] extracting $KSRC"
tar -xjf "$KSRC"
cd linux-source-6.8.0

echo "[build-kernel] configuring x86_64 (serial console + initramfs, modules off)"
make x86_64_defconfig >/dev/null
./scripts/config \
  --enable BLK_DEV_INITRD \
  --enable RD_GZIP \
  --enable DEVTMPFS \
  --enable PROC_FS \
  --enable SYSFS \
  --enable TMPFS \
  --enable SERIAL_8250 \
  --enable SERIAL_8250_CONSOLE \
  --enable SERIAL_CORE_CONSOLE \
  --enable BINFMT_ELF \
  --disable MODULES \
  --disable WERROR
make olddefconfig >/dev/null

echo "[build-kernel] compiling bzImage (this takes a few minutes)"
make -j"$(nproc)" bzImage 2>/dev/null
cp arch/x86/boot/bzImage "$OUT"
echo "[build-kernel] done: $OUT"
KSH
chmod +x /app/build-kernel.sh

# ------------------------------------------------------------ provisioning ----
cat > /app/provision.sh <<'PSH'
#!/usr/bin/env bash
# provision.sh -- idempotently build the guest rootfs at /app/rootfs:
# static busybox core binary + applet links, account database (users bilge and
# halyard, group spinnaker), and the init scripts that make the guest boot to
# an operational shell. Re-running must never duplicate a resource.
set -euo pipefail

RF=/app/rootfs
mkdir -p "$RF"/{bin,sbin,etc,proc,sys,dev,tmp,root,home/bilge,home/halyard}

# -- core binary: exactly one copy of the distro static busybox --------------
if [ ! -f "$RF/bin/busybox" ]; then
  cp /bin/busybox "$RF/bin/busybox"
  chmod 755 "$RF/bin/busybox"
fi
# refresh applet symlinks (idempotent: busybox only adds missing links)
chroot "$RF" /bin/busybox --install -s >/dev/null 2>&1 || true

# -- account database: append-only, never writes a duplicate entry -----------
if [ ! -f "$RF/etc/passwd" ]; then
  cat > "$RF/etc/passwd" <<'EOF'
root:x:0:0:root:/root:/bin/sh
bilge:x:1001:1001:Gale Pier wheel locker:/home/bilge:/bin/sh
halyard:x:1002:1002:Gale Pier mast rigger:/home/halyard:/bin/sh
EOF
else
  grep -q '^bilge:'   "$RF/etc/passwd" || echo 'bilge:x:1001:1001:Gale Pier wheel locker:/home/bilge:/bin/sh'   >> "$RF/etc/passwd"
  grep -q '^halyard:' "$RF/etc/passwd" || echo 'halyard:x:1002:1002:Gale Pier mast rigger:/home/halyard:/bin/sh' >> "$RF/etc/passwd"
fi

if [ ! -f "$RF/etc/group" ]; then
  cat > "$RF/etc/group" <<'EOF'
root:x:0:
spinnaker:x:1000:bilge,halyard
EOF
else
  grep -q '^spinnaker:' "$RF/etc/group" || echo 'spinnaker:x:1000:bilge,halyard' >> "$RF/etc/group"
fi

if [ ! -f "$RF/etc/shadow" ]; then
  cat > "$RF/etc/shadow" <<'EOF'
root:!:19701:0:99999:7:::
bilge:!:19701:0:99999:7:::
halyard:!:19701:0:99999:7:::
EOF
else
  grep -q '^bilge:'   "$RF/etc/shadow" || echo 'bilge:!:19701:0:99999:7:::'   >> "$RF/etc/shadow"
  grep -q '^halyard:' "$RF/etc/shadow" || echo 'halyard:!:19701:0:99999:7:::' >> "$RF/etc/shadow"
fi

# -- init scripts (overwrite: idempotent by construction) --------------------
cat > "$RF/etc/fstab" <<'EOF'
proc /proc proc defaults 0 0
sysfs /sys sysfs defaults 0 0
EOF

cat > "$RF/init" <<'EOF'
#!/bin/sh
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev || mount -t tmpfs tmpfs /dev
echo "=== GALE-PIER-GUEST-OPERATIONAL ==="
echo "spinnaker login: ready on ttyS0"
while :; do
  /bin/sh -i < /dev/ttyS0 > /dev/ttyS0 2>&1 || sleep 2
done
EOF
chmod 755 "$RF/init"

echo "[provision] rootfs ready at $RF"
PSH
chmod +x /app/provision.sh

# ------------------------------------------------------------------- qemu ----
cat > /app/boot-qemu.sh <<'QSH'
#!/usr/bin/env bash
# boot-qemu.sh -- pack /app/rootfs into an initramfs, boot it with the built
# kernel under QEMU (-nographic, serial console) and capture the serial log to
# /app/boot-serial.log. Exits early as soon as the operational marker appears.
set -euo pipefail

LOG=/app/boot-serial.log
INITRD=/app/rootfs.cpio.gz
rm -f "$LOG"

(cd /app/rootfs && find . -print | cpio -o -H newc 2>/dev/null | gzip -9 > "$INITRD")

(
  timeout --signal=KILL 120 qemu-system-x86_64 \
    -m 256 \
    -kernel /app/kernel/bzImage \
    -initrd "$INITRD" \
    -append "console=ttyS0" \
    -nographic \
    -no-reboot \
    > "$LOG" 2>&1
) &
QPID=$!

for i in $(seq 1 120); do
  if grep -q "GALE-PIER-GUEST-OPERATIONAL" "$LOG" 2>/dev/null; then
    kill "$QPID" 2>/dev/null || true
    wait "$QPID" 2>/dev/null || true
    echo "[boot-qemu] guest reached operational state ($LOG)"
    exit 0
  fi
  sleep 1
done

kill "$QPID" 2>/dev/null || true
wait "$QPID" 2>/dev/null || true
if grep -q "GALE-PIER-GUEST-OPERATIONAL" "$LOG"; then
  echo "[boot-qemu] guest reached operational state ($LOG)"
  exit 0
fi
echo "[boot-qemu] FAILED: no operational marker in $LOG" >&2
exit 1
QSH
chmod +x /app/boot-qemu.sh

# ------------------------------------------------------------------ legacy ----
cat > /app/legacy/pyxie.py <<'PY'
#!/usr/bin/env python3
"""Pyxie console interpreter.

Decodes /app/legacy/legacy.bin (or the file given as argv[1]) and writes, to
argv[2] (default /app/legacy/output.txt), one decimal integer per line for
every PRT instruction, in program order. See the machine contract in
/usr/src/../app/legacy/README.md (also fully described in the task brief).
"""
import struct
import sys

def wrap32(v):
    v &= 0xFFFFFFFF
    return v - 0x100000000 if v >= 0x80000000 else v

def run(data):
    regs = [0] * 16
    out = []
    n = len(data) // 8
    for i in range(n):
        rec = data[i * 8:(i + 1) * 8]
        op = rec[0]
        rd = rec[1] & 0x0F
        ra = rec[2] & 0x0F
        rb = rec[3] & 0x0F
        imm = struct.unpack('<i', rec[4:8])[0]
        if op == 0xFF:            # HALT
            break
        if op == 0x11:            # LD  rD <- imm
            regs[rd] = imm
        elif op == 0x21:          # ADD rD <- rA + rB
            regs[rd] = wrap32(regs[ra] + regs[rb])
        elif op == 0x22:          # SUB rD <- rA - rB
            regs[rd] = wrap32(regs[ra] - regs[rb])
        elif op == 0x23:          # MUL rD <- rA * rB
            regs[rd] = wrap32(regs[ra] * regs[rb])
        elif op == 0x30:          # PRT rA
            out.append(regs[ra])
        # any other opcode: instruction ignored, execution continues
    return out

def main():
    inp = sys.argv[1] if len(sys.argv) > 1 else '/app/legacy/legacy.bin'
    outp = sys.argv[2] if len(sys.argv) > 2 else '/app/legacy/output.txt'
    with open(inp, 'rb') as fh:
        data = fh.read()
    values = run(data)
    with open(outp, 'w') as fh:
        for v in values:
            fh.write('%d\n' % v)

if __name__ == '__main__':
    main()
PY

cat > /app/legacy/emulate.sh <<'ESH'
#!/usr/bin/env bash
# emulate.sh [INPUT.bin [OUTPUT.txt]]
# Runs the Pyxie interpreter over INPUT.bin and writes the program's printed
# arithmetic output to OUTPUT.txt (defaults: /app/legacy/legacy.bin and
# /app/legacy/output.txt).
set -euo pipefail
IN=${1:-/app/legacy/legacy.bin}
OUT=${2:-/app/legacy/output.txt}
python3 /app/legacy/pyxie.py "$IN" "$OUT"
ESH
chmod +x /app/legacy/emulate.sh

# -------------------------------------------------- run it all, for real -----
echo "=== running build-kernel.sh ==="
bash /app/build-kernel.sh

echo "=== running provision.sh ==="
bash /app/provision.sh
bash /app/provision.sh   # second run proves idempotency from the start

echo "=== running boot-qemu.sh ==="
bash /app/boot-qemu.sh

echo "=== running emulate.sh ==="
bash /app/legacy/emulate.sh

echo "=== oracle done ==="
ls -la /app/kernel/bzImage /app/rootfs/bin/busybox /app/boot-serial.log /app/legacy/output.txt