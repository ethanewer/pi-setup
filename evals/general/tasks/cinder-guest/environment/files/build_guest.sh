#!/bin/bash
# build_guest.sh — assembles the tiny x86_64 busybox guest (kernel + initramfs)
# that the agent's run.sh boots under qemu-system-x86_64 (software TCG, no KVM).
#
# The guest is ALWAYS x86_64, independent of the host architecture: both the
# kernel and the busybox binary come from pinned amd64 .deb archives
# (sha256-verified), because the host may be arm64 (where the distro kernel is
# an arm64 Image that qemu-system-x86_64 cannot boot). The guest rootfs is
# intentionally tiny (busybox only): the agent must drive the guest's serial
# shell over the redirected TCP port. Output lands at /app/vmlinuz (a plain
# x86_64 bzImage) and /app/guest-initrd.cpio.gz.
set -euo pipefail

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fetch() { # url sha256 out
  python3 - "$1" "$3" <<'PY'
import sys, urllib.request
urllib.request.urlretrieve(sys.argv[1], sys.argv[2])
PY
  echo "$2  $3" | sha256sum -c - >/dev/null 2>&1
  echo "build_guest: fetched $(basename "$3") (sha256 ok)"
}

KERNEL_URL="http://archive.ubuntu.com/ubuntu/pool/main/l/linux-signed/linux-image-6.8.0-138-generic_6.8.0-138.138_amd64.deb"
KERNEL_SHA="7093879c9dad61fb24bb5a0247d8dd1ea444c4854492a9b3669175624cd04bda"
BUSYBOX_URL="http://archive.ubuntu.com/ubuntu/pool/main/b/busybox/busybox-static_1.36.1-6ubuntu3.1_amd64.deb"
BUSYBOX_SHA="944b2728f53ceb3916cec2c962873c9951e612408099601751db2a0a5d81e0ed"

fetch "$KERNEL_URL" "$KERNEL_SHA" "$WORK/kernel.deb"
fetch "$BUSYBOX_URL" "$BUSYBOX_SHA" "$WORK/busybox.deb"

dpkg -x "$WORK/kernel.deb" "$WORK/kroot"
dpkg -x "$WORK/busybox.deb" "$WORK/broot"
KZ="$(ls "$WORK"/kroot/boot/vmlinuz-* | head -1)"
BB="$WORK/broot/usr/bin/busybox"
[ -f "$BB" ] || BB="$WORK/broot/bin/busybox"

python3 - "$KZ" <<'PY'
import sys
d = open(sys.argv[1], "rb").read(1024)
assert d[:2] == b"MZ" and d[0x202:0x206] == b"HdrS", \
    "kernel is not a bootable x86 bzImage (missing setup stub)"
PY
echo "build_guest: kernel is a valid x86 bzImage"

ROOT="$WORK/rootfs"
mkdir -p "$ROOT/bin" "$ROOT/dev" "$ROOT/proc" "$ROOT/sys" "$ROOT/tmp" "$ROOT/ramwork"
cp "$BB" "$ROOT/bin/busybox"
chmod 755 "$ROOT/bin/busybox"
for b in sh mount mkdir cat echo sleep poweroff pwd printf ls uname expr; do
  ln -sf busybox "$ROOT/bin/$b"
done
# an initramfs needs real console/null device nodes for init stdio
mknod -m 600 "$ROOT/dev/console" c 5 1
mknod -m 666 "$ROOT/dev/null" c 1 3

cat > "$ROOT/init" <<'INITEOF'
#!/bin/sh
mount -t proc proc /proc 2>/dev/null
mount -t sysfs sysfs /sys 2>/dev/null
echo "CINDER_GUEST_BOOT_OK"
export PS1='CG> '
echo "CINDER_GUEST_READY"
exec sh
INITEOF
chmod +x "$ROOT/init"

( cd "$ROOT" && find . -print | cpio -o -H newc --quiet ) | gzip -9 > /app/guest-initrd.cpio.gz
cp "$KZ" /app/vmlinuz
ls -la /app/guest-initrd.cpio.gz /app/vmlinuz
echo "cinder build_guest: done"