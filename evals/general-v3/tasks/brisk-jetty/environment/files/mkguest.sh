#!/bin/bash
# mkguest.sh — supplied fixture: provisions the "Nysa relay appliance" guest OS,
# a distro-less busybox+dropbear Linux image (a cpio.gz initramfs), written to
# /opt/gk/guest-initrd.cpio.gz.
#
# The OS is intentionally minimal and UNENROLLED. At boot the guest does NOT start
# sshd or the relay control panel. It brings up eth0 and presents a serial login
# console ("nysa-appliance login:"); a root operator must log in and run the
# first-run configuration steps (set the appliance hostname, run the `enroll`
# command) before sshd (:22) and the relay panel (:3733) come up. This is what
# forces the agent to automate the interactive console.
#
# Runs at image build time (see Dockerfile). Re-running it regenerates the same
# OS image from the same sources.
set -euo pipefail

GK=/opt/gk
BUSYBOX="$GK/busybox"
DEST="$GK/guest-initrd.cpio.gz"
DROPBEAR="$(command -v dropbear)"
DROPBEARKEY="$(command -v dropbearkey)"

[ -x "$BUSYBOX" ] || { echo "mkguest: missing $BUSYBOX" >&2; exit 1; }
[ -n "$DROPBEAR" ] || { echo "mkguest: dropbear not found" >&2; exit 1; }

# ---- sanity: the applets the guest relies on must exist in this busybox -------
missing=0
for a in sh login cttyhack setsid insmod ip hostname od hexdump httpd mount \
         sleep echo cat mkdir tr bash; do
  if ! printf '%s\n' "$("$BUSYBOX" --list)" | grep -qx "$a"; then
    echo "mkguest: WARN busybox lacks applet '$a'" >&2
  fi
done

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
mkdir -p "$ROOT"/{bin,sbin,etc/dropbear,etc/rc,dev,proc,sys,tmp,run,var/run,root,var/www/relay,modules,lib/x86_64-linux-gnu,usr/lib/x86_64-linux-gnu,lib64}

cp -L "$BUSYBOX" "$ROOT/bin/busybox"
( cd "$ROOT/bin" && ./busybox --list 2>/dev/null | while read -r a; do
    [ "$a" != busybox ] && ln -sf busybox "$a"
  done )

cp -L "$DROPBEAR" "$ROOT/sbin/dropbear"
cp -L "$DROPBEARKEY" "$ROOT/sbin/dropbearkey"
for l in $(ldd "$DROPBEAR" | awk '{print $3}' | grep '^/'); do
  bn=$(basename "$l")
  cp -L "$l" "$ROOT/lib/x86_64-linux-gnu/$bn" 2>/dev/null || true
  cp -L "$l" "$ROOT/usr/lib/x86_64-linux-gnu/$bn" 2>/dev/null || true
done
for l in $(ldd "$DROPBEARKEY" | awk '{print $3}' | grep '^/'); do
  bn=$(basename "$l")
  cp -L "$l" "$ROOT/lib/x86_64-linux-gnu/$bn" 2>/dev/null || true
  cp -L "$l" "$ROOT/usr/lib/x86_64-linux-gnu/$bn" 2>/dev/null || true
done
cp -L /lib64/ld-linux-x86-64.so.2 "$ROOT/lib64/" 2>/dev/null || true
cp -L /lib/x86_64-linux-gnu/ld-linux-x86-64.so.2 "$ROOT/lib/x86_64-linux-gnu/" 2>/dev/null || true

# virtio driver modules (decompressed) the guest needs to bring up its NIC.
for m in virtio virtio_ring virtio_pci virtio_net; do
  if [ -f "$GK/modules/$m.ko" ]; then cp "$GK/modules/$m.ko" "$ROOT/modules/"; fi
done

# ---- identity + accounts ------------------------------------------------------
printf 'nysa\n' > "$ROOT/etc/hostname"
printf '127.0.0.1 localhost\n' > "$ROOT/etc/hosts"
printf 'root:x:0:0:root:/root:/bin/sh\n' > "$ROOT/etc/passwd"
HASH=$(openssl passwd -6 -salt nysari "$NYSA_ROOT_PASSWORD")
printf 'root:%s:18000:0:99999:7:::\n' "$HASH" > "$ROOT/etc/shadow"

# ---- guest init: network up, then an interactive first-run login console -------
cat > "$ROOT/init" <<'INIT'
#!/bin/sh
export PATH=/bin:/sbin
mount -t proc proc /proc 2>/dev/null
mount -t sysfs sysfs /sys 2>/dev/null
mount -t devtmpfs devtmpfs /dev 2>/dev/null
mkdir -p /dev/pts /var/run /run /root
mount -t devpts devpts /dev/pts 2>/dev/null
for m in virtio virtio_ring virtio_pci virtio_net; do
  [ -f "/modules/$m.ko" ] && insmod "/modules/$m.ko" 2>/dev/null
done
sleep 1
ip link set lo up 2>/dev/null
ip link set eth0 up 2>/dev/null
ip addr add 10.0.2.15/24 dev eth0 2>/dev/null
ip route add default via 10.0.2.2 2>/dev/null
hostname "$(cat /etc/hostname)"
echo "NYSA-BOOT device=nysa-relay"
echo "NYSA-BOOT net=$(ip -o -4 addr show eth0 2>/dev/null | awk '{print $4}')"
echo
echo "Nysa relay appliance - first-run console."
echo "This unit is UNENROLLED: ssh and the relay panel are disabled until you"
echo "configure it from this console."
echo
exec setsid cttyhack /bin/login
INIT
chmod +x "$ROOT/init"

# ---- first-run enrollment command (the interactive step that configures it) ----
cat > "$ROOT/sbin/enroll" <<'ENROLL'
#!/bin/sh
# First-run enrollment for the Nysa relay appliance. Run as root from the serial
# console (after setting the appliance hostname). Generates the per-boot relay
# token, writes /etc/rc/enroll, then starts sshd (:22) and the relay panel
# (:3733) which serves /live with "RELAY-LIVE kestrel <token>".
if [ -f /etc/rc/enroll ]; then
  echo "NYSA-ALREADY-ENROLLED $(cat /etc/rc/enroll)"
  exit 0
fi
mkdir -p /etc/rc /var/www/relay /etc/dropbear /root/.ssh
H=$(cat /etc/hostname 2>/dev/null)
if ! [ -f /etc/dropbear/dropbear_ed25519_host_key ]; then
  /sbin/dropbearkey -t ed25519 -f /etc/dropbear/dropbear_ed25519_host_key >/dev/null 2>&1
fi
salt=$(/bin/od -An -N4 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')
token="$salt"
echo "enrolled=yes hostname=$H token=$token" > /etc/rc/enroll
echo "RELAY-LIVE kestrel $token" > /var/www/relay/live
/sbin/dropbear -p 22 >/dev/null 2>&1 &
/bin/busybox httpd -f -p 3733 -h /var/www/relay >/dev/null 2>&1 &
echo "NYSA-READY token=$token"
ENROLL
chmod +x "$ROOT/sbin/enroll"

( cd "$ROOT" && find . | cpio -o -H newc 2>/dev/null | gzip -9 > "$DEST" )
echo "mkguest: built $DEST"
ls -la "$DEST"
echo "mkguest: done"
