#!/bin/bash
# build_guest.sh — assembles the tiny-busybox guest (kernel + custom initramfs)
# that the agent's run.sh boots under qemu-system-x86_64 (software TCG, no KVM).
#
# The guest rootfs is intentionally tiny (busybox + the 9p/virtio kernel modules
# that are modules rather than built-in). A full C toolchain is NOT baked into
# the guest; instead run.sh 9p-shares the container root into the guest and the
# guest chroots into it to compile, which keeps the guest light and keeps the
# build under the image budget. Output lands at /app/guest-initrd.cpio.gz and
# /app/vmlinuz.
set -euo pipefail

KV="$(ls /lib/modules | tail -1)"
echo "iris build_guest: kernel=$KV"

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
mkdir -p "$ROOT/bin" "$ROOT/dev" "$ROOT/proc" "$ROOT/sys" "$ROOT/tmp" "$ROOT/etc" "$ROOT/hr"
mkdir -p "$ROOT/lib/modules/net/9p" "$ROOT/lib/modules/fs/9p" "$ROOT/lib/modules/fs/netfs"

cp /usr/bin/busybox "$ROOT/bin/busybox"
for b in sh mount ls cat echo mkdir sleep reboot poweroff cpio pwd uname df insmod lsmod chroot date modprobe printf; do
  ln -sf busybox "$ROOT/bin/$b"
done

# 9p filesystem + its deps are modules in the generic kernel; decompress them so
# the (module-busybox) guest can `insmod` the plain ELF directly.
for kv in "$KV"; do
  zstd -d -q "/lib/modules/$kv/kernel/net/9p/9pnet.ko.zst"      -o "$ROOT/lib/modules/net/9p/9pnet.ko"
  zstd -d -q "/lib/modules/$kv/kernel/net/9p/9pnet_virtio.ko.zst" -o "$ROOT/lib/modules/net/9p/9pnet_virtio.ko"
  zstd -d -q "/lib/modules/$kv/kernel/fs/netfs/netfs.ko.zst"      -o "$ROOT/lib/modules/fs/netfs/netfs.ko"
  zstd -d -q "/lib/modules/$kv/kernel/fs/9p/9p.ko.zst"            -o "$ROOT/lib/modules/fs/9p/9p.ko"
done

cat > "$ROOT/init" <<'INITEOF'
#!/bin/sh
mount -t proc proc /proc 2>/dev/null
mount -t sysfs sysfs /sys 2>/dev/null
M=/lib/modules
insmod $M/net/9p/9pnet.ko 2>/dev/null
insmod $M/net/9p/9pnet_virtio.ko 2>/dev/null
insmod $M/fs/netfs/netfs.ko 2>/dev/null
insmod $M/fs/9p/9p.ko 2>/dev/null
echo "IRIS_GUEST_BOOT_OK"
if mount -t 9p -o trans=virtio,version=9p2000.L hostroot /hr 2>/tmp/hre; then
  echo "IRIS_HOSTROOT_MOUNT_OK"
  if [ -x /hr/opt/iris/guest_work.sh ]; then
    chroot /hr /bin/bash /opt/iris/guest_work.sh
    echo "IRIS_GUEST_WORK_RETURNED"
  else
    echo "IRIS_NO_WORK_SCRIPT"
  fi
else
  echo "IRIS_HOSTROOT_MOUNT_FAILED"
  cat /tmp/hre 2>/dev/null
fi
echo "IRIS_GUEST_IDLE"
exec sh
INITEOF
chmod +x "$ROOT/init"

( cd "$ROOT" && find . -print | busybox cpio -o -H newc ) 2>/dev/null | gzip -9 > /app/guest-initrd.cpio.gz
cp "/boot/vmlinuz-$KV" /app/vmlinuz
ls -la /app/guest-initrd.cpio.gz /app/vmlinuz
echo "iris build_guest: done"