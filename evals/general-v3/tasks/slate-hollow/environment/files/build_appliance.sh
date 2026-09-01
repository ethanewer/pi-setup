#!/bin/bash
# build_appliance.sh — assembles the guest-support artifacts baked into the
# image for slate-hollow:
#
#   /app/vmlinuz      — a pinned x86_64 bzImage Linux kernel (from an Ubuntu
#                       jammy 5.15 signed kernel .deb; plain bzImage so QEMU
#                       can attach an initrd to it)
#   /app/base.cpio.gz — a deliberately TRIVIAL x86_64 busybox initramfs. It
#                       ships ONLY busybox + applet symlinks + device nodes.
#                       Its default init mounts nothing but /dev, prints one
#                       banner and drops to a bare shell. It does NOT mount
#                       proc/sys, has NO user accounts, and starts NO getty:
#                       injecting that real init is the agent's task.
#
# Both guest artifacts are pinned amd64 builds so the appliance guest is
# always x86_64 regardless of the host architecture (QEMU runs it under TCG).
set -euo pipefail

KERNEL_DEB_URL="http://archive.ubuntu.com/ubuntu/pool/main/l/linux-signed/linux-image-5.15.0-25-generic_5.15.0-25.25_amd64.deb"
BUSYBOX_DEB_URL="http://archive.ubuntu.com/ubuntu/pool/main/b/busybox/busybox-static_1.36.1-6ubuntu3_amd64.deb"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "slate build_appliance: fetching pinned guest artifacts"
curl -fsSL -o "$TMP/kernel.deb" "$KERNEL_DEB_URL"
curl -fsSL -o "$TMP/busybox.deb" "$BUSYBOX_DEB_URL"

# --- prebuilt x86_64 kernel (plain bzImage) -------------------------
dpkg-deb -x "$TMP/kernel.deb" "$TMP/kernel"
KV="$(ls "$TMP/kernel/boot/vmlinuz-"* | head -1)"
cp "$KV" /app/vmlinuz
echo "slate build_appliance: vmlinuz -> /app/vmlinuz ($(basename "$KV"))"

# --- x86_64 static busybox ------------------------------------------
dpkg-deb -x "$TMP/busybox.deb" "$TMP/busybox"
BB="$(find "$TMP/busybox" -type f -name busybox | head -1)"
if [ -z "$BB" ]; then echo "no busybox found in deb"; exit 1; fi

# --- trivial base initramfs ----------------------------------------
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT" "$TMP"' EXIT
mkdir -p "$ROOT/bin" "$ROOT/sbin" "$ROOT/dev" "$ROOT/proc" "$ROOT/sys" \
         "$ROOT/etc" "$ROOT/tmp" "$ROOT/home"

cp "$BB" "$ROOT/bin/busybox"
for b in sh ash mount umount cat echo printf mkdir rm cp mv ls sleep \
         setsid getty login id hostname pwd sync poweroff uname grep sed \
         cut tr mknod chmod chown true false; do
  ln -sf busybox "$ROOT/bin/$b"
done

# device nodes so early console works even before devtmpfs is mounted
mknod -m 600 "$ROOT/dev/console" c 5 1
mknod -m 666 "$ROOT/dev/null"    c 1 3
mknod -m 660 "$ROOT/dev/ttyS0"   c 4 64
mknod -m 666 "$ROOT/dev/tty"     c 5 0

# Trivial init: minimal device setup and a bare shell. No login, no getty,
# no accounts, no proc/sys. Everything real must be injected by the agent.
cat > "$ROOT/init" <<'INITEOF'
#!/bin/sh
mount -t devtmpfs devtmpfs /dev 2>/dev/null
echo RESCUE_BASE_INIT
exec sh
INITEOF
chmod +x "$ROOT/init"

( cd "$ROOT" && find . | cpio -o -H newc 2>/dev/null | gzip -9 > /app/base.cpio.gz )
echo "slate build_appliance: base.cpio.gz -> /app/base.cpio.gz ($(stat -c%s /app/base.cpio.gz) bytes)"
