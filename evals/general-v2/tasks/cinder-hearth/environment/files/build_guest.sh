#!/bin/bash
# build_guest.sh — assembles the two guest-support artifacts baked into the
# image for cinder-hearth:
#
#   /app/vmlinuz               — a prebuilt Linux kernel for the guest (x86_64)
#   /app/base-initrd.cpio.gz   — a deliberately TRIVIAL busybox initramfs
#
# The base init only prints a marker and drops to a shell. It does NOT mount
# /proc, /sys, or /dev (beyond whatever the kernel provides), does NOT create
# /etc/passwd or /etc/group, and does NOT start a getty or login on the serial
# console. Injecting a real init that enables unauthenticated serial login is
# the agent's task. Do not modify either artifact.
set -euo pipefail

echo "cinder build_guest: kernel=$(ls /lib/modules | tail -1)"

# --- prebuilt kernel ------------------------------------------------
cp "$(ls /boot/vmlinuz-* | tail -1)" /app/vmlinuz
echo "cinder build_guest: vmlinuz -> /app/vmlinuz"

# --- trivial base initramfs ----------------------------------------
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
mkdir -p "$ROOT/bin" "$ROOT/dev" "$ROOT/proc" "$ROOT/sys" "$ROOT/etc" \
         "$ROOT/tmp" "$ROOT/root" "$ROOT/home" "$ROOT/seed"

cp /usr/bin/busybox "$ROOT/bin/busybox"
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
