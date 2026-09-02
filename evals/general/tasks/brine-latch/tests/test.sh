#!/bin/bash
# Verifier for brine-latch: checks the visible deliverables (/app/reclaim.py,
# /app/recovered.bin byte-exact vs the known visible snapshot), ENFORCES the
# no-disturb rules on /app/vault, and EXECUTES the deliverable program against
# fresh hidden relay processes holding different payloads. Writes REWARD (0/1)
# to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

PRISTINE_DECOY_SHA="e45e0f378efddba3c4567e0fd2a4689fe190cb0d4bce83234e289305fed49880"

no_modify_broken=0
if [ ! -f /app/vault/decoy.txt ]; then
    echo "no-modify: /app/vault/decoy.txt missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/vault/decoy.txt | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_DECOY_SHA" ]; then
        echo "no-modify: /app/vault/decoy.txt was modified" >&2
        no_modify_broken=1
    fi
fi
if [ -f /app/vault/payload.bin ]; then
    echo "no-modify: /app/vault/payload.bin reappeared (relay was disturbed?)" >&2
    no_modify_broken=1
fi

python3 - "$no_modify_broken" <<'PY'
import os, shutil, subprocess, sys, tempfile, time

SOLVER = "/app/reclaim.py"
VISIBLE_SHA = "dd48257ce52c48b04e80753fa51d64b1de6d6845862090a2e614ade17ee3ed76"
no_modify_broken = int(sys.argv[1])
failures = []


def sha(data):
    import hashlib
    return hashlib.sha256(data).hexdigest()


def wait_for_pidfile(path, timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if os.path.isfile(path):
            try:
                with open(path) as f:
                    pid = int(f.read().strip())
                os.kill(pid, 0)
                return pid
            except (OSError, ValueError):
                pass
        time.sleep(0.1)
    return None


def run_hidden_case(payload_path, tag):
    work = tempfile.mkdtemp(prefix="bl_case_")
    src = os.path.join(work, "snapshot.bin")
    shutil.copyfile(payload_path, src)
    pidfile = os.path.join(work, "relay.pid")
    # spawn a fresh relay holding the payload open and unlinking its name
    code = (
        "import os, sys, time\n"
        "src, pidfile = sys.argv[1], sys.argv[2]\n"
        "fd = os.open(src, os.O_RDONLY)\n"
        "decoy = os.open(src + '.live', os.O_RDONLY | os.O_CREAT)\n"
        "os.unlink(src)\n"
        "open(pidfile, 'w').write(str(os.getpid()))\n"
        "os.pread(fd, 4, 0)\n"
        "time.sleep(180)\n"
    )
    proc = subprocess.Popen([sys.executable, "-c", code, src, pidfile],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        pid = wait_for_pidfile(pidfile)
        if pid is None:
            failures.append("%s: keeper did not start" % tag)
            return
        out = os.path.join(work, "recovered.bin")
        r = subprocess.run([sys.executable, SOLVER, pidfile, out],
                           capture_output=True, text=True, timeout=120)
        if r.returncode != 0 or not os.path.isfile(out):
            failures.append("%s: reclaim.py failed: %s" % (tag, r.stderr[-200:]))
            return
        with open(out, "rb") as f:
            got = f.read()
        with open(payload_path, "rb") as f:
            want = f.read()
        if got != want:
            failures.append("%s: recovered bytes mismatch (%d vs %d bytes)"
                            % (tag, len(got), len(want)))
    finally:
        proc.kill()
        proc.wait()
        shutil.rmtree(work, ignore_errors=True)


if no_modify_broken:
    failures.append("visible vault modified or disturbed (no-modify rule)")

if not os.path.isfile(SOLVER):
    failures.append("missing /app/reclaim.py")
else:
    # hidden cases: execute the deliverable against fresh relay processes
    hidden_dir = "/tests/hidden"
    cases = sorted(os.listdir(hidden_dir)) if os.path.isdir(hidden_dir) else []
    if not cases:
        failures.append("no hidden cases present")
    for c in cases:
        p = os.path.join(hidden_dir, c, "payload.bin")
        if os.path.isfile(p):
            run_hidden_case(p, "hidden:%s" % c)
        else:
            failures.append("hidden '%s' malformed (no payload.bin)" % c)

    # visible deliverable: /app/recovered.bin must be byte-exact
    if os.path.isfile("/app/recovered.bin"):
        with open("/app/recovered.bin", "rb") as f:
            got = f.read()
        if sha(got) != VISIBLE_SHA:
            failures.append("/app/recovered.bin content mismatch (%d bytes)"
                            % len(got))
    else:
        failures.append("missing /app/recovered.bin")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
