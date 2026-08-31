#!/bin/bash
# Verifier for slate-hollow: checks deliverables, validates the captured
# console.log, then INDEPENDENTLY boots the appliance initramfs under QEMU with
# its own serial driver — logging in as the visible user and as hidden users
# built via /app/mkinit.sh — and verifies in-guest: pseudo-fs mounts, uid 1000,
# and the exact username. Writes 1 or 0 to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

fail() { echo "0" > /logs/verifier/reward.txt; echo "VERIFIER FAIL: $1"; exit 0; }

for f in /app/mkinit.sh /app/drive.sh /app/appliance.cpio.gz /app/console.log; do
  [ -e "$f" ] || fail "missing deliverable $f"
done
[ -x /app/mkinit.sh ] || fail "/app/mkinit.sh not executable"
[ -x /app/drive.sh ] || fail "/app/drive.sh not executable"

# console.log content (guarded)
grep -aq "RESCUE_APPLIANCE_READY" /app/console.log || fail "console.log lacks RESCUE_APPLIANCE_READY"
grep -aq "login:" /app/console.log || fail "console.log lacks a login prompt"
grep -aq "RESCUE_LOGIN_OK" /app/console.log || fail "console.log lacks RESCUE_LOGIN_OK"

# the agent's own driver must work on the visible appliance
rm -rf /tmp/slate_vdrive && mkdir -p /tmp/slate_vdrive
bash /app/drive.sh /app/appliance.cpio.gz rescue /tmp/slate_vdrive \
  || fail "drive.sh failed on the visible appliance"
grep -aq "RESCUE_LOGIN_OK" /tmp/slate_vdrive/console.log \
  || fail "drive.sh console.log lacks RESCUE_LOGIN_OK"

python3 - <<'PY'
import os, re, select, subprocess, sys, tempfile, time

fails = []

def boot_and_login(appliance, user, boot_timeout=150):
    """Boot the appliance, log in as `user`, run in-guest checks.
    Returns (ok, list_of_problems)."""
    problems = []
    cmd = [
        "qemu-system-x86_64", "-accel", "tcg", "-m", "256M",
        "-kernel", "/app/vmlinuz", "-initrd", appliance,
        "-append", "console=ttyS0 rdinit=/init panic=-1",
        "-display", "none", "-monitor", "none", "-serial", "stdio", "-no-reboot",
    ]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                            stderr=subprocess.DEVNULL)
    state = {"buf": b"", "pos": 0}
    deadline = time.time() + boot_timeout

    def pump(pattern, chunk_deadline=45):
        rx = re.compile(pattern.encode() if isinstance(pattern, str) else pattern)
        start = time.time()
        while time.time() < deadline and time.time() - start < chunk_deadline:
            if rx.search(state["buf"][state["pos"]:]):
                return True
            r, _, _ = select.select([proc.stdout], [], [], 1.0)
            if r:
                chunk = os.read(proc.stdout.fileno(), 65536)
                if not chunk:
                    return bool(rx.search(state["buf"][state["pos"]:]))
                state["buf"] += chunk
            elif proc.poll() is not None:
                return bool(rx.search(state["buf"][state["pos"]:]))
        return False

    def send(text):
        try:
            proc.stdin.write(text.encode())
            proc.stdin.flush()
        except OSError:
            pass

    def drain(text):
        state["buf"] += text.encode()

    try:
        if not pump(r"RESCUE_APPLIANCE_READY", boot_timeout):
            problems.append("marker RESCUE_APPLIANCE_READY never appeared")
            return False, problems
        if not pump(rb"login:"):
            problems.append("no login: prompt on serial console")
            return False, problems
        time.sleep(0.5)
        send(user + "\n")
        time.sleep(2.0)
        send("echo RESCUE_LOGIN_OK\n")
        if not pump(r"RESCUE_LOGIN_OK"):
            problems.append("login as %r did not yield a shell (RESCUE_LOGIN_OK missing)"
                            % user)
            return False, problems
        # pseudo-fs mounts inside the guest (cat /proc/mounts only works if
        # proc was mounted by the injected init)
        send("echo M_BEGIN; cat /proc/mounts; echo M_END\n")
        if not pump(r"M_END"):
            problems.append("could not read /proc/mounts inside guest")
            return False, problems
        seg = state["buf"][state["pos"]:]
        state["pos"] = len(state["buf"])
        seg_s = seg.decode("utf-8", "replace")
        for fsname in ("proc", "sysfs", "devtmpfs"):
            if not re.search(r"(?m)^\s*%s[ /]" % re.escape(fsname), seg_s) and \
               fsname not in seg_s:
                problems.append("pseudo-fs %s not mounted" % fsname)
        # identity checks
        send("echo I_BEGIN; id -u; id -un; echo I_END\n")
        if not pump(r"I_END"):
            problems.append("could not read id output inside guest")
            return False, problems
        seg = state["buf"][state["pos"]:]
        state["pos"] = len(state["buf"])
        seg_s = seg.decode("utf-8", "replace")
        if not re.search(r"(?m)^1000\r?$", seg_s):
            problems.append("id -u is not 1000 (unauthenticated account missing)")
        if not re.search(r"(?m)^%s\r?$" % re.escape(user), seg_s):
            problems.append("id -un is not %r" % user)
        return not problems, problems
    finally:
        try:
            proc.kill()
        except OSError:
            pass

# --- visible appliance, independent boot ----------------------------------
ok, probs = boot_and_login("/app/appliance.cpio.gz", "rescue")
if not ok:
    fails.append("visible appliance: " + "; ".join(probs))

# --- hidden users: rebuild appliance via mkinit.sh, then boot -------------
hidden_dir = "/tests/hidden"
users = sorted(f for f in os.listdir(hidden_dir)
               if (os.path.join(hidden_dir, f, "user.txt"))) \
        if os.path.isdir(hidden_dir) else []
if len(users) < 2:
    fails.append("expected >=2 hidden user cases, found %d" % len(users))
for u in users:
    try:
        want = open(os.path.join(hidden_dir, u, "user.txt")).read().strip()
    except OSError:
        fails.append("hidden case %s unreadable" % u)
        continue
    with tempfile.TemporaryDirectory() as td:
        r = subprocess.run(["bash", "/app/mkinit.sh", want, td],
                           capture_output=True, text=True, timeout=180)
        app = os.path.join(td, "appliance.cpio.gz")
        if r.returncode != 0 or not os.path.isfile(app):
            fails.append("mkinit.sh failed for hidden user %s: %s"
                         % (want, (r.stderr or "")[-200:]))
            continue
        ok, probs = boot_and_login(app, want)
        if not ok:
            fails.append("hidden user %s: " % want + "; ".join(probs))

print("verify failures:", fails)
sys.exit(1 if fails else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
