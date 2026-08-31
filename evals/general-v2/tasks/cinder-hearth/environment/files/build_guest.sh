#!/bin/bash
# build_guest.sh — assembles the two guest-support artifacts baked into the
# image for cinder-hearth:
#
#   /app/vmlinuz               — a prebuilt x86_64 Linux kernel for the guest
#   /app/base-initrd.cpio.gz   — a deliberately TRIVIAL busybox initramfs
#
# The base init only prints a marker and drops to a shell. It does NOT mount
# /proc, /sys, or /dev, does NOT create /etc/passwd or /etc/group, and does
# NOT start a getty or login on the serial console. Injecting a real init that
# enables unauthenticated serial login is the agent's task.
#
# The image build may run on a non-amd64 host, so the x86_64 kernel and the
# x86_64 static busybox are pulled as amd64 packages (download-only, then
# dpkg -x) and must be a classic bzImage (HdrS) that qemu's x86 loader accepts.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

dpkg --add-architecture amd64
apt-get update -qq
apt-get install -y -qq --no-install-recommends --download-only \
    linux-image-amd64:amd64 busybox-static:amd64

ARC=/var/cache/apt/archives
mkdir -p /tmp/kx /tmp/bb
dpkg -x "$ARC"/linux-image-*deb*-amd64_*.deb /tmp/kx
dpkg -x "$ARC"/busybox-static_*_amd64.deb /tmp/bb

KERN="$(ls /tmp/kx/boot/vmlinuz-* | tail -1)"
cp "$KERN" /app/vmlinuz
python3 - <<PYCHECK
d = open("/app/vmlinuz", "rb").read(0x210)
assert d[0x202:0x206] == b"HdrS", "kernel is not a classic x86 bzImage"
print("cinder build_guest: bzImage header OK")
PYCHECK
echo "cinder build_guest: vmlinuz -> /app/vmlinuz ($(stat -c%s /app/vmlinuz) bytes)"

# --- trivial base initramfs (x86_64 userland) -----------------------
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
mkdir -p "$ROOT/bin" "$ROOT/dev" "$ROOT/proc" "$ROOT/sys" "$ROOT/etc" \
         "$ROOT/tmp" "$ROOT/root" "$ROOT/home" "$ROOT/seed"

cp /tmp/bb/usr/bin/busybox "$ROOT/bin/busybox"
for b in sh ash mount umount mkdir cat echo cp rm mv sed grep printf sleep \
         setsid cttyhack login getty chmod chown ln ls sync ps id; do
  ln -sf busybox "$ROOT/bin/$b"
done

# Trivial init: marker + shell. No login, no getty, no /etc/passwd.
cat > "$ROOT/init" <<'INITEOF'
#!/bin/sh
echo CINDER_BASE_INIT
exec sh
INITEOF
chmod +x "$ROOT/init"

( cd "$ROOT" && find . | cpio -o -H newc 2>/dev/null | gzip -9 > /app/base-initrd.cpio.gz )
echo "cinder build_guest: base-initrd -> /app/base-initrd.cpio.gz ($(stat -c%s /app/base-initrd.cpio.gz) bytes)"
