#!/bin/bash
# /app/run.sh — cinder-guest driver.
#
# Boots a tiny busybox guest under QEMU software emulation (TCG, no KVM) with a
# telnet-served QEMU monitor and a TCP-redirected serial console, both on
# loopback ports. Waits for the guest boot markers, then drives the guest's
# serial shell over the redirected port: mounts a tmpfs at /ramwork, computes
# a op b in-guest with shell arithmetic, writes "<token>|<result>" to
# /ramwork/answer.txt, cats it back over serial, verifies the monitor with
# `info status`, writes OUTDIR/result.json, and leaves qemu running in the
# background.
#
# Usage: /app/run.sh [SCENARIO_JSON] [OUTDIR]
set -u

SCN="${1:-/app/scenario-main.json}"
OUT="${2:-/app}"

if [ ! -f "$SCN" ]; then
  echo "cinder-guest: scenario file $SCN missing" >&2
  exit 2
fi
mkdir -p "$OUT"

read_scn() { python3 -c "import json,sys;print(json.load(open('$SCN')).get('$1',''))"; }
A=$(read_scn a)
B=$(read_scn b)
OP=$(read_scn op)
MP=$(read_scn monitor_port)
SP=$(read_scn serial_port)
NAME=$(read_scn name); [ -n "$NAME" ] || NAME=scenario

if [ -z "$A" ] || [ -z "$B" ] || [ -z "$OP" ] || [ -z "$MP" ] || [ -z "$SP" ]; then
  echo "cinder-guest: bad scenario file $SCN" >&2
  exit 2
fi

# ---- clean any stale qemu -------------------------------------------------
pkill -f qemu-system-x86_64 2>/dev/null || true
sleep 1

rm -f "$OUT/serial.txt" "$OUT/monitor.txt" "$OUT/result.json"
LOG="$OUT/qemu-$NAME.log"

# ---- boot the guest in the background -------------------------------------
setsid qemu-system-x86_64 \
  -accel tcg \
  -kernel /app/vmlinuz \
  -initrd /app/guest-initrd.cpio.gz \
  -append "console=ttyS0 panic=-1 rdinit=/init" \
  -m 256M -nographic -no-reboot -no-shutdown \
  -monitor "telnet:127.0.0.1:$MP,server,nowait" \
  -serial "tcp:127.0.0.1:$SP,server,nowait" \
  >"$LOG" 2>&1 &

sleep 1
QPID="$(pgrep -f qemu-system-x86_64 | head -1)"

python3 - "$SCN" "$OUT" "$QPID" <<'DRIVER'
import json, os, re, socket, sys, time

scn_path, out_dir, qpid_raw = sys.argv[1], sys.argv[2], sys.argv[3]
scn = json.load(open(scn_path))
a, b, op = int(scn["a"]), int(scn["b"]), scn["op"]
token = str(scn.get("token", ""))
mp, sp = int(scn["monitor_port"]), int(scn["serial_port"])
name = str(scn.get("name", "scenario"))

expected = {"add": a + b, "sub": a - b, "mul": a * b}[op]
expr = {"add": "%d + %d" % (a, b),
        "sub": "%d - %d" % (a, b),
        "mul": "%d * %d" % (a, b)}[op]


def connect(port, timeout=120):
    end = time.time() + timeout
    last = None
    while time.time() < end:
        try:
            s = socket.create_connection(("127.0.0.1", port), timeout=10)
            s.settimeout(5)
            return s
        except OSError as e:
            last = e
            time.sleep(0.5)
    raise RuntimeError("cannot connect to 127.0.0.1:%d (%s)" % (port, last))


# ---------- serial console: drive the guest shell --------------------------
ser = connect(sp)
tr = bytearray()
serial_ok = True


def read_until(sock, buf, pat, timeout):
    end = time.time() + timeout
    while time.time() < end:
        if re.search(pat, bytes(buf)):
            return True
        try:
            chunk = sock.recv(4096)
        except socket.timeout:
            continue
        except OSError:
            time.sleep(0.1)
            continue
        if chunk:
            buf.extend(chunk)
    return bool(re.search(pat, bytes(buf)))


def send_cmd(sock, buf, cmd, timeout=60):
    sock.sendall(cmd.encode() + b"\n")
    return read_until(sock, buf, rb"CG> ", timeout)


if not read_until(ser, tr, rb"CINDER_GUEST_READY", 150):
    serial_ok = False
# nudge a fresh prompt, then drive the guest
ser.sendall(b"\n")
read_until(ser, tr, rb"CG> ", 30)
send_cmd(ser, tr, "mkdir -p /ramwork")
send_cmd(ser, tr, "mount -t tmpfs tmpfs /ramwork && echo CG_MOUNT_OK")
if b"CG_MOUNT_OK" not in bytes(tr):
    serial_ok = False
send_cmd(ser, tr,
         'R=$((%s)); echo "%s|$R" > /ramwork/answer.txt; cat /ramwork/answer.txt'
         % (expr, token))

text = bytes(tr).decode("latin-1")
m = re.search(r"^%s\|(\d+)\s*$" % re.escape(token), text, re.M)
guest_answer = int(m.group(1)) if m else None
if m is None:
    serial_ok = False

# ---------- monitor console: HMP verification ------------------------------
mon = connect(mp)
mtr = bytearray()
mon_ok = read_until(mon, mtr, rb"\(qemu\)", 60)
mon.sendall(b"\n")
mon_ok = read_until(mon, mtr, rb"\(qemu\)", 30) and mon_ok
mon.sendall(b"info status\n")
mon_ok = read_until(mon, mtr, rb"\(qemu\)", 60) and mon_ok
mon_ok = mon_ok and (b"running" in bytes(mtr))

with open(os.path.join(out_dir, "serial.txt"), "w", encoding="latin-1") as fh:
    fh.write(text)
with open(os.path.join(out_dir, "monitor.txt"), "w", encoding="latin-1") as fh:
    fh.write(bytes(mtr).decode("latin-1"))

qpid = int(qpid_raw) if str(qpid_raw).strip().isdigit() else -1
qemu_alive = False
if qpid > 0:
    try:
        os.kill(qpid, 0)
        qemu_alive = True
    except OSError:
        qemu_alive = False

result = {
    "task": "cinder-guest",
    "scenario": name,
    "a": a,
    "b": b,
    "op": op,
    "token": token,
    "expected": expected,
    "guest_answer": guest_answer,
    "answer_ok": guest_answer == expected,
    "serial_ok": serial_ok,
    "monitor_ok": mon_ok,
    "monitor_port": mp,
    "serial_port": sp,
    "qemu_pid": qpid,
    "qemu_alive": qemu_alive,
    "background": True,
}
with open(os.path.join(out_dir, "result.json"), "w") as fh:
    json.dump(result, fh, indent=2)
sys.exit(0 if (serial_ok and mon_ok and result["answer_ok"]) else 3)
DRIVER
rc=$?

exit $rc