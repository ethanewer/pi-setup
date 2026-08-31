#!/bin/bash
# build_guest.sh — assembles the tiny-busybox guest (kernel + custom initramfs)
# that the agent's run.sh boots under qemu-system-x86_64 (software TCG, no KVM).
#
# The guest rootfs is intentionally tiny (busybox only): the agent must drive
# the guest's serial shell over the redirected TCP port. Output lands at
# /app/guest-initrd.cpio.gz and /app/vmlinuz.
set -euo pipefail

KV="$(ls /lib/modules | tail -1)"
echo "cinder build_guest: kernel=$KV"

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
mkdir -p "$ROOT/bin" "$ROOT/dev" "$ROOT/proc" "$ROOT/sys" "$ROOT/tmp"

cp /usr/bin/busybox "$ROOT/bin/busybox"
for b in sh mount mkdir cat echo sleep poweroff pwd printf ls uname expr; do
  ln -sf busybox "$ROOT/bin/$b"
done

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

( cd "$ROOT" && find . -print | busybox cpio -o -H newc ) 2>/dev/null | gzip -9 > /app/guest-initrd.cpio.gz
cp "/boot/vmlinuz-$KV" /app/vmlinuz
ls -la /app/guest-initrd.cpio.gz /app/vmlinuz
echo "cinder build_guest: done"