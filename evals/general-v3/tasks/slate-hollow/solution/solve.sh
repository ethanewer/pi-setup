#!/bin/bash
# Oracle for slate-hollow: author mkinit.sh + drive.sh, build the appliance for
# the visible user `rescue`, and capture a real serial login session into
# /app/console.log. Never reads /tests.
set -euo pipefail

# ---------------------------------------------------------- 1. mkinit.sh
cat > /app/mkinit.sh <<'MK_EOF'
#!/bin/bash
# mkinit.sh USERNAME OUTDIR -> OUTDIR/appliance.cpio.gz
set -euo pipefail
USER_NAME="${1:?usage: mkinit.sh USERNAME OUTDIR}"
OUTDIR="${2:?usage: mkinit.sh USERNAME OUTDIR}"
if ! [[ "$USER_NAME" =~ ^[a-z_][a-z0-9_-]{0,15}$ ]]; then
  echo "mkinit.sh: bad username '$USER_NAME'" >&2; exit 2
fi
mkdir -p "$OUTDIR"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/root"
( cd "$WORK/root" && gzip -dc /app/base.cpio.gz | cpio -idm --quiet )

# ---- injected init ----
cat > "$WORK/root/init" <<INIT_EOF
#!/bin/sh
export PATH=/bin:/sbin
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
echo RESCUE_APPLIANCE_READY
hostname appliance 2>/dev/null || true
mkdir -p /home/$USER_NAME /root
cat > /etc/passwd <<PW_EOF
root::0:0:root:/root:/bin/sh
$USER_NAME::1000:1000:Rescue:/home/$USER_NAME:/bin/sh
PW_EOF
cat > /etc/group <<GR_EOF
root::0:
$USER_NAME::1000:
GR_EOF
chmod 444 /etc/passwd /etc/group
while true; do
  setsid busybox getty -L ttyS0 115200 vt100
done
INIT_EOF
chmod +x "$WORK/root/init"

( cd "$WORK/root" && find . | cpio -o -H newc --quiet | gzip -9 ) > "$OUTDIR/appliance.cpio.gz"
echo "mkinit.sh: wrote $OUTDIR/appliance.cpio.gz for user $USER_NAME"
MK_EOF
chmod +x /app/mkinit.sh

# ---------------------------------------------------------- 2. drive.sh
cat > /app/drive.sh <<'DR_EOF'
#!/bin/bash
# drive.sh APPLIANCE USERNAME OUTDIR -> OUTDIR/console.log, exit 0 on login
set -euo pipefail
APPLIANCE="${1:?usage: drive.sh APPLIANCE USERNAME OUTDIR}"
USER_NAME="${2:?usage: drive.sh APPLIANCE USERNAME OUTDIR}"
OUTDIR="${3:?usage: drive.sh APPLIANCE USERNAME OUTDIR}"
mkdir -p "$OUTDIR"
python3 - "$APPLIANCE" "$USER_NAME" "$OUTDIR/console.log" <<'PY'
import os, re, select, subprocess, sys, time

appliance, user, logpath = sys.argv[1], sys.argv[2], sys.argv[3]
deadline_total = time.time() + 240

cmd = [
    "qemu-system-x86_64", "-accel", "tcg", "-m", "256M",
    "-kernel", "/app/vmlinuz", "-initrd", appliance,
    "-append", "console=ttyS0 rdinit=/init panic=-1",
    "-display", "none", "-monitor", "none", "-serial", "stdio", "-no-reboot",
]
proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                        stderr=subprocess.DEVNULL)
buf = b""
log = open(logpath, "wb")

def pump(deadline, pattern=None):
    """Read until pattern matches or deadline; returns match or None."""
    global buf
    rx = re.compile(pattern.encode() if isinstance(pattern, str) else pattern) if pattern else None
    while time.time() < deadline:
        if rx and rx.search(buf):
            return True
        r, _, _ = select.select([proc.stdout], [], [], 1.0)
        if r:
            chunk = os.read(proc.stdout.fileno(), 65536)
            if not chunk:
                return rx.search(buf) if rx else False
            buf += chunk
            log.write(chunk)
            log.flush()
        elif proc.poll() is not None:
            return rx.search(buf) if rx else False
    return rx.search(buf) if rx else False

def send(text):
    proc.stdin.write(text.encode())
    proc.stdin.flush()

try:
    ok = True
    if not pump(deadline_total, r"RESCUE_APPLIANCE_READY"):
        ok = False
    if ok and not pump(deadline_total, rb"login:?"):
        ok = False
    if ok:
        time.sleep(0.5)
        send(user + "\n")
        time.sleep(2.0)
        send("echo RESCUELOGIN\"OK\"\n")
        if not pump(deadline_total, r"RESCUELOGINOK"):
            ok = False
    sys.exit(0 if ok else 1)
finally:
    try:
        proc.kill()
    except OSError:
        pass
    log.close()
PY
DR_EOF
chmod +x /app/drive.sh

# ------------------------------------------- 3. visible appliance + log
bash /app/mkinit.sh rescue /app
bash /app/drive.sh /app/appliance.cpio.gz rescue /app
echo "console.log bytes: $(stat -c%s /app/console.log)"
grep -a "RESCUELOGINOK" /app/console.log >/dev/null && echo "login marker present"
echo "slate-hollow oracle: done"
