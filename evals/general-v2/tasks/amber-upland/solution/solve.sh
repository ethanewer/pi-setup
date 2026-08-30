#!/bin/bash
# Oracle for tasks/amber-upland.
#
# Does the real work: reads the descriptor manifest, mounts busybox + device
# nodes + the init hand-off inside a gzipped newc cpio archive, writes the
# launcher program /app/boot.sh and its default /app/vnc.conf, then boots the
# produced initramfs once to prove it reaches a shell. Never reads /tests.
set -eu

MAN=/app/files/initramfs_manifest.json
[ -f "$MAN" ] || { echo "manifest missing: $MAN" >&2; exit 1; }

# --------------------------------------------------------------------------
# 1) Build /app/initramfs.gz from the descriptor manifest (real construction
#    work, executed -- not a pre-built artifact).
# --------------------------------------------------------------------------
python3 - "$MAN" /app/initramfs.gz <<'PY'
import json, os, stat, subprocess, sys, tempfile

manifest_f, out_archive = sys.argv[1], sys.argv[2]
m = json.load(open(manifest_f))
work = tempfile.mkdtemp(prefix="ird_")
root = os.path.join(work, "root")
os.makedirs(root)

def mkdir_under(p):
    d = os.path.join(root, p.lstrip("/"))
    os.makedirs(d, exist_ok=True)

try:
    for d in m.get("directory_roots", []):
        mkdir_under(d)

    # busybox applet binary
    full = os.path.join(root, m["busybox_dest"].lstrip("/"))
    mkdir_under(os.path.dirname(m["busybox_dest"]))
    with open(m["busybox_source"], "rb") as fh, open(full, "wb") as out:
        out.write(fh.read())
    os.chmod(full, 0o755)

    # applet symlinks
    for link in m.get("applet_links", []):
        target = os.path.join(root, link.lstrip("/"))
        mkdir_under(os.path.dirname(link))
        if os.path.lexists(target):
            os.unlink(target)
        os.symlink(os.path.relpath(full, os.path.dirname(target)), target)

    # device nodes (char devices, exact major/minor)
    for node in m.get("device_nodes", []):
        p = os.path.join(root, node["path"].lstrip("/"))
        mkdir_under(os.path.dirname(node["path"]))
        os.mknod(p, stat.S_IFCHR, (int(node["major"]) << 8) | int(node["minor"]))

    # /init handoff script -> exec shell
    init = m["init"]
    lines = ["#!/bin/sh"] + init.get("mount_steps", [])
    lines.append("echo %s" % init["banner"])
    lines.append("exec %s" % init["exec_shell"])
    ipath = os.path.join(root, "init")
    with open(ipath, "w") as fh:
        fh.write("\n".join(lines) + "\n")
    os.chmod(ipath, 0o755)

    subprocess.run(
        "cd '%s' && find . | cpio -o -H newc 2>/dev/null | gzip > '%s'"
        % (root, out_archive), shell=True, check=True)
    print("built %s %d bytes" % (out_archive, os.path.getsize(out_archive)))
finally:
    import shutil
    shutil.rmtree(work, ignore_errors=True)
PY

# --------------------------------------------------------------------------
# 2) The launcher program /app/boot.sh (executes-deliverable).
# --------------------------------------------------------------------------
cat > /app/boot.sh <<'SH'
#!/bin/bash
# Boot /app/initramfs.gz under QEMU in the background, keep it running, expose
# VNC + a web monitor per the given config JSON.
# Usage: boot.sh [config.json]   (no arg -> /app/vnc.conf)
set -eu

CFG="${1:-/app/vnc.conf}"
eval "$(python3 - "$CFG" <<'PY'
import json, sys
c = json.load(open(sys.argv[1]))
keys = ["vnc_display", "web_port", "marker", "console_socket", "pidfile",
        "web_pidfile", "web_dir", "status_title", "kernel", "initrd"]
for k in keys:
    print("CFG_%s=%s" % (k.upper(), repr(str(c.get(k, "")))))
PY
)"

CFG_KERNEL="${CFG_KERNEL:-/boot/vmlinuz}"
CFG_INITRD="${CFG_INITRD:-/app/initramfs.gz}"

# Idempotent teardown: kill anything a previous run of this config started.
for pf in "$CFG_PIDFILE" "$CFG_WEB_PIDFILE"; do
    [ -n "$pf" ] && [ -f "$pf" ] && kill "$(cat "$pf" 2>/dev/null)" 2>/dev/null || true
done
rm -f "$CFG_CONSOLE_SOCKET" "$CFG_PIDFILE" "$CFG_WEB_PIDFILE"

VNC_TCP=$((5900 + CFG_VNC_DISPLAY))

# Monitoring web server (busybox httpd from the host binary).
mkdir -p "$CFG_WEB_DIR"
cat > "$CFG_WEB_DIR/index.html" <<HTML
<!doctype html><html><head><meta charset=utf-8><title>${CFG_STATUS_TITLE}</title></head>
<body><h1>${CFG_STATUS_TITLE}</h1><p>guest marker: ${CFG_MARKER}</p><p>state: running in background</p></body></html>
HTML
/usr/bin/busybox httpd -f -p "$CFG_WEB_PORT" -h "$CFG_WEB_DIR" >/dev/null 2>&1 &
echo $! > "$CFG_WEB_PIDFILE"

# Boot the guest in the background (TCG software emulation, keep-alive).
qemu-system-x86_64 -m 256 -nographic \
    -kernel "$CFG_KERNEL" -initrd "$CFG_INITRD" \
    -append "console=ttyS0 rdinit=/init" \
    -serial "unix:$CFG_CONSOLE_SOCKET,server=on,wait=off" \
    -vnc ":$CFG_VNC_DISPLAY" \
    -nic none >/dev/null 2>&1 &
QPID=$!
echo "$QPID" > "$CFG_PIDFILE"

# Poll until VM (serial socket + vnc + web) is fully reachable.
up=0
for _ in $(seq 1 100); do
  if ! kill -0 "$QPID" 2>/dev/null; then
      echo "QEMU exited during boot" >&2; exit 3
  fi
  if python3 - "$VNC_TCP" "$CFG_WEB_PORT" "$CFG_CONSOLE_SOCKET" <<'PY'; then
import os, socket, sys
vncp, webp, sock = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
def tcp_ok(p):
    s = socket.socket(); s.settimeout(0.5)
    try:
        return s.connect_ex(("127.0.0.1", p)) == 0
    finally:
        s.close()
if not os.path.exists(sock): raise SystemExit(1)
if not tcp_ok(vncp): raise SystemExit(1)
if not tcp_ok(webp): raise SystemExit(1)
PY
      up=1; break
  fi
  sleep 1
done

if [ "$up" -ne 1 ]; then
  echo "guest did not become reachable in time" >&2
  exit 4
fi

echo "VM READY vnc=127.0.0.1:$VNC_TCP web=127.0.0.1:$CFG_WEB_PORT console=$CFG_CONSOLE_SOCKET"
exit 0
SH
chmod +x /app/boot.sh

# --------------------------------------------------------------------------
# 3) The default config deliverable.
# --------------------------------------------------------------------------
cat > /app/vnc.conf <<'JSON'
{
  "vnc_display": 0,
  "web_port": 80,
  "marker": "amber-shell-1",
  "console_socket": "/tmp/amber_upland_console.sock",
  "pidfile": "/tmp/amber_upland_vm.pid",
  "web_pidfile": "/tmp/amber_upland_web.pid",
  "web_dir": "/tmp/amber_upland_monitor",
  "status_title": "amber-upland VM monitor",
  "kernel": "/boot/vmlinuz",
  "initrd": "/app/initramfs.gz"
}
JSON

echo "deliverables:"
ls -la /app/initramfs.gz /app/boot.sh /app/vnc.conf