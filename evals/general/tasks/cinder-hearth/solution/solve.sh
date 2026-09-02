#!/bin/bash
# Oracle for cinder-hearth: author the injector + console driver, create the
# main scenario, and run it to produce the injected initramfs and session log.
# From a pristine container; never reads /tests.
set -eu

cat > /app/mkinit.sh <<'MK_EOF'
#!/bin/bash
# mkinit.sh <scenario.json> <out_initrd>
# Injects a real init into a copy of /app/base-initrd.cpio.gz: mounts the
# pseudo-fs, embeds the scenario token, sets up unauthenticated accounts,
# and hands the serial console to login.
set -euo pipefail

SCN="${1:?usage: mkinit.sh <scenario.json> <out_initrd>}"
OUT="${2:?usage: mkinit.sh <scenario.json> <out_initrd>}"

WORK="$(mktemp -d /tmp/cinder_init_XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

# 1) extract the pristine base initramfs
mkdir -p "$WORK/tree"
( cd "$WORK/tree" && gzip -dc /app/base-initrd.cpio.gz | cpio -idm )

# 2) scenario values
USER_NAME="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["user"])' "$SCN")"
TOKEN="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["token"])' "$SCN")"

# 3) embedded mission seed
mkdir -p "$WORK/tree/seed"
printf '%s\n' "$TOKEN" > "$WORK/tree/seed/token.txt"

# 4) unauthenticated accounts: empty password fields for root and user
cat > "$WORK/tree/etc/passwd" <<PASS_EOF
root::0:0:root:/root:/bin/sh
${USER_NAME}::1000:100:${USER_NAME}:/home/${USER_NAME}:/bin/sh
PASS_EOF
cat > "$WORK/tree/etc/group" <<GRP_EOF
root::0:
${USER_NAME}::1000:
GRP_EOF
mkdir -p "$WORK/tree/home/$USER_NAME" "$WORK/tree/root"

# 5) the injected init
cat > "$WORK/tree/init" <<INIT_EOF
#!/bin/sh
export PATH=/bin
mount -t proc proc /proc && mount -t sysfs sysfs /sys && mount -t devtmpfs devtmpfs /dev
echo CINDER_BOOT_OK
echo CINDER_PSEUDOFS_OK
cat /seed/token.txt >/dev/null
echo "CINDER_SEED_TOKEN=\$(cat /seed/token.txt)"
echo CINDER_SERIAL_TTY=ttyS0
echo CINDER_READY_FOR_LOGIN
exec setsid cttyhack /bin/login
INIT_EOF
chmod 755 "$WORK/tree/init"

# 6) repack
mkdir -p "$(dirname "$OUT")"
( cd "$WORK/tree" && find . | cpio -o -H newc 2>/dev/null | gzip -9 > "$OUT" )
echo "mkinit: wrote $OUT (user=$USER_NAME)"
MK_EOF
chmod +x /app/mkinit.sh

cat > /app/console_drive.py <<'CD_EOF'
#!/usr/bin/env python3
"""console_drive.py <initrd> <scenario.json> <out_log>

Boots the cinder-hearth guest under QEMU TCG with the given initramfs, drives
the serial console to an unauthenticated login, captures the whole session to
<out_log>, and leaves the emulator running as a background service.
"""
import json
import socket
import subprocess
import sys
import time


def main():
    if len(sys.argv) != 4:
        print("usage: console_drive.py <initrd> <scenario.json> <out_log>")
        return 2
    initrd, scn_path, out_log = sys.argv[1], sys.argv[2], sys.argv[3]
    scn = json.load(open(scn_path))
    port = int(scn["serial_port"])
    user = scn["user"]

    # 1) free the port / kill stale emulators
    subprocess.run(["pkill", "-f", "qemu-system"], capture_output=True)
    time.sleep(0.5)

    # 2) boot in the background (TCG only, serial on a loopback TCP port)
    qlog = open("/tmp/cinder_qemu.log", "wb")
    cmd = [
        "qemu-system-x86_64", "-accel", "tcg",
        "-kernel", "/app/vmlinuz", "-initrd", initrd,
        "-append", "console=ttyS0 panic=-1 rdinit=/init",
        "-m", "256M", "-no-reboot", "-display", "none",
        "-serial", "tcp:127.0.0.1:%d,server,nowait" % port,
    ]
    proc = subprocess.Popen(cmd, stdout=qlog, stderr=qlog,
                            start_new_session=True)

    # 3) connect to the serial port
    sock = None
    deadline = time.time() + 60
    while time.time() < deadline:
        try:
            sock = socket.create_connection(("127.0.0.1", port), timeout=2)
            break
        except OSError:
            time.sleep(0.2)
    if sock is None:
        print("cannot connect to serial port %d" % port)
        return 1

    buf = b""

    def pump_until(needle, timeout):
        nonlocal buf
        end = time.time() + timeout
        while needle not in buf:
            if time.time() > end:
                return False
            sock.settimeout(2.0)
            try:
                d = sock.recv(4096)
            except socket.timeout:
                continue
            except OSError:
                return False
            if not d:
                return False
            buf += d
        return True

    rc = 0
    try:
        if not pump_until(b"login:", 300):
            print("timeout waiting for login prompt")
            rc = 1
        else:
            sock.sendall((user + "\n").encode())
            # An unauthenticated account should not prompt; be robust anyway.
            pump_until(b"Password:", 8)
            time.sleep(1.0)
            sock.sendall(b"\n")
            time.sleep(1.0)
            sock.sendall(b"echo CINDER_AUTH_OK\n")
            if not pump_until(b"CINDER_AUTH_OK", 90):
                print("timeout waiting for CINDER_AUTH_OK")
                rc = 1
            else:
                time.sleep(1.0)
    finally:
        try:
            sock.close()
        except Exception:
            pass
        with open(out_log, "wb") as fh:
            fh.write(buf)
    print("console_drive: rc=%d log=%s bytes=%d" % (rc, out_log, len(buf)))
    return rc


if __name__ == "__main__":
    sys.exit(main())
CD_EOF
chmod +x /app/console_drive.py

# Main scenario + deliverables
cat > /app/scenario-main.json <<'SCN_EOF'
{
  "name": "main",
  "user": "deckhand",
  "token": "CINDER-HEARTH-MAIN-412",
  "serial_port": 56123
}
SCN_EOF

bash /app/mkinit.sh /app/scenario-main.json /app/guest-initrd.cpio.gz
python3 /app/console_drive.py /app/guest-initrd.cpio.gz /app/scenario-main.json /app/session.log

echo "cinder-hearth solve done"
ls -l /app/mkinit.sh /app/console_drive.py /app/guest-initrd.cpio.gz /app/session.log /app/scenario-main.json
