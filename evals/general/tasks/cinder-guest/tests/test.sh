#!/bin/bash
# cinder-guest verifier. Runs as root after the agent finishes.
# /tests and /solution are mounted read-only; the agent worked in /app.
#
# Re-executes the deliverable (/app/run.sh) on the main scenario and on each
# hidden scenario, asserting per case:
#   * OUTDIR/result.json reports answer_ok / serial_ok / monitor_ok /
#     qemu_alive / background all true and guest_answer == reference(a op b)
#   * the serial transcript contains the "<token>|<result>" line the guest
#     produced
#   * the monitor console (loopback telnet port) still answers an HMP command
#   * the serial console (loopback TCP port) still shows the CG> shell prompt
#     and executes a fresh probe command — the emulator is a live, drivable
#     background service
set -u

REWARD=/logs/verifier/reward.txt
mkdir -p /logs/verifier
fail() { echo "VERIFY-FAIL: $*" >&2; echo 0 > "$REWARD"; exit 1; }
okay() { echo "REWARD-OK: $*" >&2; echo 1 > "$REWARD"; exit 0; }

[ -f /app/run.sh ] || fail "/app/run.sh missing"
[ -x /app/run.sh ] || fail "/app/run.sh not executable"

ports_of() { # scn -> "MONITOR_PORT SERIAL_PORT"
  python3 -c "import json,sys;s=json.load(open(sys.argv[1]));print(s['monitor_port'],s['serial_port'])" "$1"
}

probe_monitor() { # port -> 0 if live HMP answering
  python3 - "$1" <<'PY'
import socket, sys, time

port = int(sys.argv[1])
try:
    s = socket.create_connection(("127.0.0.1", port), timeout=15)
    s.settimeout(10)
    end = time.time() + 45

    def read_until(buf, pat):
        while time.time() < end:
            if pat in buf:
                return buf
            try:
                c = s.recv(4096)
            except socket.timeout:
                continue
            except OSError:
                break
            if not c:
                break
            buf += c
        return buf

    s.sendall(b"\n")
    buf = read_until(b"", b"(qemu)")
    if b"(qemu)" not in buf:
        sys.exit(1)
    s.sendall(b"info status\n")
    resp = b""
    while time.time() < end:
        try:
            c = s.recv(4096)
        except socket.timeout:
            continue
        except OSError:
            break
        if not c:
            break
        resp += c
        if b"VM status" in resp and b"(qemu)" in resp:
            break
    ok = (b"running" in resp) and (b"VM status" in resp)
    sys.exit(0 if ok else 1)
except Exception:
    sys.exit(1)
PY
}

probe_serial() { # port -> 0 if live guest shell answering
  python3 - "$1" <<'PY'
import socket, sys, time

port = int(sys.argv[1])
try:
    s = socket.create_connection(("127.0.0.1", port), timeout=15)
    s.settimeout(10)
    end = time.time() + 45
    # a newline elicits a fresh CG> prompt from the waiting guest shell
    s.sendall(b"\n")
    buf = b""
    while time.time() < end and b"CG> " not in buf:
        try:
            c = s.recv(4096)
        except socket.timeout:
            continue
        except OSError:
            break
        if not c:
            break
        buf += c
    if b"CG> " not in buf:
        sys.exit(1)
    s.sendall(b"echo CGPROBE$((41+1))\n")
    resp = b""
    while time.time() < end and b"CG> " not in resp:
        try:
            c = s.recv(4096)
        except socket.timeout:
            continue
        except OSError:
            break
        if not c:
            break
        resp += c
    ok = b"CGPROBE42" in resp
    sys.exit(0 if ok else 1)
except Exception:
    sys.exit(1)
PY
}

check_result() { # scn_path outdir
  python3 - "$1" "$2" <<'PY'
import json, os, sys

scn_path, outdir = sys.argv[1], sys.argv[2]
s = json.load(open(scn_path))
a, b, op = int(s["a"]), int(s["b"]), s["op"]
expected = {"add": a + b, "sub": a - b, "mul": a * b}[op]
rp = os.path.join(outdir, "result.json")
assert os.path.isfile(rp), "missing result.json in " + outdir
r = json.load(open(rp))
assert r.get("task") == "cinder-guest", r
assert r.get("scenario") == s.get("name", "scenario"), r
assert (r.get("a"), r.get("b"), r.get("op")) == (a, b, op), r
assert r.get("token") == s.get("token", ""), r
assert r.get("monitor_port") == int(s["monitor_port"]), r
assert r.get("serial_port") == int(s["serial_port"]), r
assert r.get("expected") == expected, r
assert r.get("guest_answer") == expected, (
    "guest_answer %r != expected %d" % (r.get("guest_answer"), expected))
assert r.get("answer_ok") is True, r
assert r.get("serial_ok") is True, r
assert r.get("monitor_ok") is True, r
assert r.get("qemu_alive") is True, r
assert r.get("background") is True, r

stxt = os.path.join(outdir, "serial.txt")
assert os.path.isfile(stxt), "missing serial transcript in " + outdir
txt = open(stxt, encoding="latin-1").read()
assert ("%s|%d" % (s.get("token", ""), expected)) in txt, \
    "tokenized answer line missing from serial transcript"
mtxt = os.path.join(outdir, "monitor.txt")
assert os.path.isfile(mtxt) and os.path.getsize(mtxt) > 0, \
    "missing monitor transcript in " + outdir
PY
}

run_case() { # src_json
  local src="$1"
  local outdir="/tmp/cg_case_${RANDOM}$$"
  rm -rf "$outdir"; mkdir -p "$outdir"
  bash /app/run.sh "$src" "$outdir" >/tmp/cg_run.log 2>&1 \
    || fail "run.sh failed for $src: $(tail -5 /tmp/cg_run.log)"
  check_result "$src" "$outdir" || fail "result checks failed for $src"
  local ports
  ports=$(ports_of "$src")
  probe_monitor "$(echo "$ports" | cut -d' ' -f1)" \
    || fail "monitor probe failed for $src (ports $ports)"
  probe_serial "$(echo "$ports" | cut -d' ' -f2)" \
    || fail "serial probe failed for $src (ports $ports)"
  rm -rf "$outdir"
}

# ---- main scenario + deliverable /app/result.json --------------------------
bash /app/run.sh >/tmp/cg_run_main.log 2>&1 \
  || fail "run.sh (default args) failed: $(tail -5 /tmp/cg_run_main.log)"
check_result /app/scenario-main.json /app \
  || fail "/app/result.json inconsistent with /app/scenario-main.json"
MP=$(ports_of /app/scenario-main.json | cut -d' ' -f1)
SP=$(ports_of /app/scenario-main.json | cut -d' ' -f2)
probe_monitor "$MP" || fail "monitor probe failed on main (port $MP)"
probe_serial "$SP" || fail "serial probe failed on main (port $SP)"

# ---- hidden cases ----------------------------------------------------------
[ -d /tests/hidden ] || fail "/tests/hidden missing"
count=0
for src in /tests/hidden/*.json; do
  [ -f "$src" ] || continue
  run_case "$src"
  count=$((count + 1))
done
[ "$count" -ge 2 ] || fail "expected >=2 hidden cases, got $count"

okay "main + $count hidden cases passed"