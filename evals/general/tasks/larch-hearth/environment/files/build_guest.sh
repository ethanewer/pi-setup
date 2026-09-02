#!/bin/bash
# build_guest.sh — assembles the two guest-support artifacts baked into the
# image for larch-hearth:
#
#   /app/vmlinuz                — a prebuilt Linux kernel for the guest
#   /app/base-initrd.cpio.gz    — a deliberately TRIVIAL busybox initramfs
#
# The base-initrd intentionally does NOT enable serial login, does NOT mount
# the cdrom, and does NOT set up the 9p host-root work flow: injecting that real
# init is the agent's task. The base only ships busybox plus the decompressed
# kernel modules the guest will need (isofs for the cdrom, 9p for the shared
# host root) so an injected init can `insmod` them directly.
set -euo pipefail

KV="$(ls /lib/modules | tail -1)"
echo "larch build_guest: kernel=$KV"

# --- prebuilt kernel ------------------------------------------------
cp "$(ls /boot/vmlinuz-* | tail -1)" /app/vmlinuz
echo "larch build_guest: vmlinuz -> /app/vmlinuz"

# --- trivial base initramfs ----------------------------------------
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
mkdir -p "$ROOT/bin" "$ROOT/dev" "$ROOT/proc" "$ROOT/sys" "$ROOT/etc" "$ROOT/tmp" "$ROOT/cd" "$ROOT/hr"
mkdir -p "$ROOT/lib/modules/fs/isofs" "$ROOT/lib/modules/net/9p" "$ROOT/lib/modules/fs/9p" "$ROOT/lib/modules/fs/netfs"

cp /usr/bin/busybox "$ROOT/bin/busybox"
for b in sh mount ls cat echo mkdir sleep insmod modprobe cpio chroot setsid login cttyhack sed grep printf cp rm; do
  ln -sf busybox "$ROOT/bin/$b"
done

# Decompress the modules the guest needs so a plain `insmod` of the ELF works.
zstd -d -q "/lib/modules/$KV/kernel/fs/isofs/isofs.ko.zst"      -o "$ROOT/lib/modules/fs/isofs/isofs.ko"
zstd -d -q "/lib/modules/$KV/kernel/net/9p/9pnet.ko.zst"        -o "$ROOT/lib/modules/net/9p/9pnet.ko"
zstd -d -q "/lib/modules/$KV/kernel/net/9p/9pnet_virtio.ko.zst" -o "$ROOT/lib/modules/net/9p/9pnet_virtio.ko"
zstd -d -q "/lib/modules/$KV/kernel/fs/netfs/netfs.ko.zst"      -o "$ROOT/lib/modules/fs/netfs/netfs.ko"
zstd -d -q "/lib/modules/$KV/kernel/fs/9p/9p.ko.zst"            -o "$ROOT/lib/modules/fs/9p/9p.ko"

# Trivial init: mount device nodes and drop to a shell. No login, no cdrom,
# no 9p. Any competent guest behavior must be injected by the agent.
cat > "$ROOT/init" <<'INITEOF'
#!/bin/sh
mount -t devtmpfs devtmpfs /dev 2>/dev/null
echo LARCH_BASE_INIT
exec sh
INITEOF
chmod +x "$ROOT/init"

( cd "$ROOT" && find . | cpio -o -H newc 2>/dev/null | gzip -9 > /app/base-initrd.cpio.gz )
echo "larch build_guest: base-initrd -> /app/base-initrd.cpio.gz ($(stat -c%s /app/base-initrd.cpio.gz) bytes)"
