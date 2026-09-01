#!/bin/bash
# fern-terrace builder: turn a minimal *guest profile* into a running software-emulated
# Linux guest (password SSH, persistent background emulator) and recover a marker file
# from a legacy raw disk image at its partition offset.
#
#   build_guest.sh PROFILE.json OUTDIR
#
# PROFILE.json fields:
#   hostname        guest hostname (e.g. "fringe-north")
#   password        root SSH password
#   port            host port that forwards to the guest's sshd:22
#   service_token   opaque string written to /etc/service-token in the guest
#   disk            optional path to a LEGACY RAW DISK IMAGE to read (hidden case).
#                   if absent/missing a fresh disk is generated for this profile.
#   marker_path     absolute path of the marker file inside the fs (default /media/data/marker)
#   marker_expected content that must be recovered from the disk's partition
#
# Outputs into OUTDIR:
#   guest.iso                  ISO-9660 bundle (kernel + initrd + profile)
#   serial.log                 boot console capture (must show FERN-BOOT-READY)
#   disk.img                   the raw disk used (generated, or copied input)
#   extracted/marker           the marker bytes recovered at its partition offset
#   ssh.ready                  "1" once password SSH to the running guest is verified
#
# The emulator is intentionally left running as a background service when done.
set -u

PROFILE="$1"; OUT="$2"
mkdir -p "$OUT/extracted"

PY=python3
KERNEL=/opt/gk/vmlinuz
BUSYBOX=/opt/gk/busybox
DROPBEAR="$(command -v dropbear)"
DROPBEARKEY="$(command -v dropbearkey)"

# ---------- read profile ----------
eval "$($PY - "$PROFILE" <<'PYEOF'
import json,sys
d=json.load(open(sys.argv[1]))
for k in ('hostname','password','port','service_token'):
    print('%s=%r' % (k,d.get(k)))
print('DISK=%r' % (d.get('disk') or ''))
print('MARKER_PATH=%r' % (d.get('marker_path') or '/media/data/marker'))
print('MARKER_EXPECTED=%r' % (d.get('marker_expected') or ''))
PYEOF
)"

# ---------- 1) raw disk : generate if not provided ----------
if [ -n "${DISK:-}" ] && [ -f "$DISK" ]; then
    cp "$DISK" "$OUT/disk.img"
    echo ">>> using provided raw disk $DISK"
else
    echo ">>> no disk provided; generating a raw legacy disk for this profile"
    # place the partition at a non-trivial, profile-derived offset (real LBA bytes)
    START_LBA=$(( 900 + ( ${#hostname} * 7 ) % 4096 ))
    : > /tmp/mkbody.$$ ; printf '%s' "$MARKER_EXPECTED" > /tmp/fsbody.$$
    truncate -s $(( 16384 * 512 )) /tmp/part.$$
    mke2fs -F -t ext2 -b 4096 /tmp/part.$$ >/dev/null 2>&1
    {
        echo "mkdir /media"; echo "mkdir /media/data"
        echo "write /tmp/fsbody.$$ $MARKER_PATH"
        echo "quit"
    } > /tmp/fsdbg.$$
    debugfs -w -f /tmp/fsdbg.$$ /tmp/part.$$ >/dev/null 2>&1
    TOTAL=$(( (START_LBA + 16384) * 512 ))
    truncate -s "$TOTAL" "$OUT/disk.img"
    $PY - "$OUT/disk.img" "$START_LBA" <<'PY'
import sys,struct
f,l=sys.argv[1],int(sys.argv[2])
b=bytearray(open(f,'rb').read())
b[510:512]=b'\x55\xaa'
e=bytearray(b[446:462]); e[4]=0x83
e[8:12]=struct.pack('<I',l); e[12:16]=struct.pack('<I',16384)
b[446:462]=e
open(f,'wb').write(bytes(b))
PY
    dd if=/tmp/part.$$ of="$OUT/disk.img" bs=512 seek="$START_LBA" conv=notrunc status=none
fi
chmod 644 "$OUT/disk.img"

# ---------- 2) recover the marker at its partition offset ----------
$PY - "$OUT/disk.img" "$MARKER_PATH" "$OUT/extracted/marker" <<'PY'
import sys,struct,os,subprocess
disk,mpath,out=sys.argv[1],sys.argv[2],sys.argv[3]
b=open(disk,'rb').read(512); e=b[446:462]
typ=e[4]; lba=struct.unpack('<I',e[8:12])[0]; ns=struct.unpack('<I',e[12:16])[0]
if typ!=0x83: sys.exit('not a linux partition (type=%02x)'%typ)
part=out+'.part'
with open(disk,'rb') as r, open(part,'wb') as w:
    r.seek(lba*512); w.write(r.read(ns*512))
subprocess.run(['debugfs','-R','dump %s %s'%(mpath,out),part],
               check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
os.unlink(part)
print('recovered marker at start_lba=%d'%lba)
PY
echo "recovered-marker=$(cat "$OUT/extracted/marker" 2>/dev/null)"

# ---------- 3) build the guest initramfs ----------
ROOT=$(mktemp -d)
mkdir -p "$ROOT/bin" "$ROOT/sbin" "$ROOT/etc/dropbear" "$ROOT/dev" "$ROOT/sys" \
         "$ROOT/proc" "$ROOT/tmp" "$ROOT/run" "$ROOT/root" "$ROOT/mnt" \
         "$ROOT/lib/x86_64-linux-gnu" "$ROOT/usr/lib/x86_64-linux-gnu" "$ROOT/lib64" "$ROOT/etc"
cp -L "$BUSYBOX" "$ROOT/bin/busybox"
( cd "$ROOT/bin" && ./busybox --list 2>/dev/null | while read a; do [ "$a" = busybox ] || ln -sf busybox "$a"; done )
cp -L "$DROPBEAR" "$ROOT/sbin/dropbear"
for l in $(ldd "$DROPBEAR" | awk '{print $3}' | grep '^/'); do
    re=$(readlink -f "$l"); bn=$(basename "$l")
    cp -L "$re" "$ROOT/lib/x86_64-linux-gnu/$bn" 2>/dev/null || true
    cp -L "$re" "$ROOT/usr/lib/x86_64-linux-gnu/$bn" 2>/dev/null || true
done
cp -L /lib64/ld-linux-x86-64.so.2 "$ROOT/lib64/"
"$DROPBEARKEY" -t rsa -f "$ROOT/etc/dropbear/dropbear_rsa_host_key" -s 2048 >/dev/null 2>&1
HASH=$(openssl passwd -6 -salt fermx "$password")
printf 'root:x:0:0:root:/root:/bin/sh\n' > "$ROOT/etc/passwd"
printf 'root:%s:18000:0:99999:7:::\n' "$HASH" > "$ROOT/etc/shadow"
printf '%s\n' "$hostname" > "$ROOT/etc/hostname"
printf '%s' "$service_token" > "$ROOT/etc/service-token"
printf '127.0.0.1 localhost\n' > "$ROOT/etc/hosts"
: > "$ROOT/etc/resolv.conf"

cat > "$ROOT/init" <<'INIT'
#!/bin/sh
export PATH=/bin:/sbin
mount -t proc proc /proc; mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev 2>/dev/null
mkdir -p /dev/pts /var/run /root; mount -t devpts devpts /dev/pts 2>/dev/null
hostname "$(cat /etc/hostname)"
echo "FERN-BOOT host=$(hostname)"
echo "FERN-SERVICE-TOKEN=$(cat /etc/service-token)"
ip link set lo up 2>/dev/null
ip link set eth0 up 2>/dev/null || echo "NO-ETH0"
ip addr add 10.0.2.15/24 dev eth0 2>/dev/null || true
ip route add default via 10.0.2.2 2>/dev/null || true
/sbin/dropbear -p 22 -r /etc/dropbear/dropbear_rsa_host_key >/dev/null 2>&1
echo "FERN-BOOT-READY"
while true; do echo "FERN-KEEPALIVE $(date)"; sleep 10; done
INIT
chmod +x "$ROOT/init"
( cd "$ROOT" && find . | cpio -o -H newc 2>/dev/null | gzip -9 > "$OUT/initrd.gz" )
rm -rf "$ROOT"

# ---------- 4) bundle the guest CD image ----------
ISOD=$(mktemp -d)
mkdir -p "$ISOD/boot"
cp "$KERNEL" "$ISOD/boot/kernel"
cp "$OUT/initrd.gz" "$ISOD/boot/initrd.gz"
cp "$PROFILE" "$ISOD/boot/profile.json"
printf '%s' "$service_token" > "$ISOD/boot/token.txt"
genisoimage -quiet -o "$OUT/guest.iso" "$ISOD" 2>/dev/null
rm -rf "$ISOD"
cp "$KERNEL" "$OUT/kernel"
cp -L "$BUSYBOX" "$OUT/busybox"

# ---------- 5) boot the guest under software emulation (background service) ----------
pkill -9 -f "hostfwd=tcp:127.0.0.1:$port" 2>/dev/null || true
qemu-system-x86_64 \
  -machine pc,accel=tcg -m 512 -smp 1 -display none \
  -kernel "$OUT/kernel" -initrd "$OUT/initrd.gz" \
  -append "console=ttyS0 rdinit=/init panic=-1 nokaslr quiet" \
  -cdrom "$OUT/guest.iso" \
  -netdev user,id=n0,hostfwd=tcp:127.0.0.1:$port-:22 \
  -device virtio-net-pci,netdev=n0 \
  -serial file:"$OUT/serial.log" 2>>"$OUT/qemu.err" &
echo $! > "$OUT/qemu.pid"

# ---------- 6) verify password SSH host -> guest, then leave running ----------
GREP_OK=0
for i in $(seq 1 60); do
    if grep -q FERN-BOOT-READY "$OUT/serial.log" 2>/dev/null; then GREP_OK=1; break; fi
    sleep 2
done
SSH_OK=0
if [ "$GREP_OK" = 1 ]; then
    for i in $(seq 1 20); do
        if sshpass -p "$password" ssh -p "$port" -oStrictHostKeyChecking=no \
             -oUserKnownHostsFile=/dev/null -oConnectTimeout=2 root@127.0.0.1 \
             "cat /etc/service-token; hostname" > "$OUT/ssh.check" 2>/dev/null; then
            SSH_OK=1; break
        fi
        sleep 1
    done
fi
echo "$SSH_OK" > "$OUT/ssh.ready"
echo "$(cat "$OUT/ssh.check" 2>/dev/null)" > "$OUT/ssh.result"
echo ">>> serial boot: $(grep -c FERN-BOOT-READY "$OUT/serial.log" 2>/dev/null)"
echo ">>> ssh ready:   $SSH_OK"
echo ">>> emulator alive: $(kill -0 "$(cat "$OUT/qemu.pid")" 2>/dev/null && echo yes || echo no)"
sleep 1
