#!/bin/bash
# Verifier for silt-barrow: checks the visible deliverables, ENFORCES that no
# non-wanted archive member (notably hostkeys.pem) was materialized and that
# the archive + coexisting live recorder.log are untouched, then EXECUTES the
# deliverable /app/extract.sh on the visible bundle and on every hidden bundle.
# Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

failures=""

PIN_ARCH="564aac7f997aab783303a39a161a62417d9abdab19e637ff490083920a0a6add"
PIN_LOG="d93e084ef3f13802d202577d4c2a843dcef6debbb2ab2a86064fa84473c8fcbb"

sha_of() { sha256sum "$1" 2>/dev/null | cut -d' ' -f1; }

# ------------------------------------------------------------------ visible
[ -f /app/bundle/incident.tar.gz ] || failures="$failures visible archive missing;"
[ -f /app/bundle/recorder.log ] || failures="$failures visible live log missing;"
[ "$(sha_of /app/bundle/incident.tar.gz)" = "$PIN_ARCH" ] \
  || failures="$failures visible incident.tar.gz modified;"
[ "$(sha_of /app/bundle/recorder.log)" = "$PIN_LOG" ] \
  || failures="$failures visible live recorder.log clobbered;"

# no sensitive / non-wanted member may sit on disk anywhere under /app
for bad in hostkeys.pem snapshot.bin manifest.txt; do
    hits="$(find /app -name "$bad" -not -path '*/tests/*' 2>/dev/null)"
    [ -z "$hits" ] || failures="$failures sensitive member materialized: $bad;"
done
# the live log must not have been overwritten with the archive's member
extra="$(find /app/bundle -type f 2>/dev/null | grep -v -e '/incident.tar.gz$' -e '/recorder.log$')"
[ -z "$extra" ] || failures="$failures unexpected files in /app/bundle: $extra;"

[ -f /app/extract.sh ] || failures="$failures missing /app/extract.sh;"

python3 - <<'PY'
import os, shutil, subprocess, sys, tarfile, tempfile

failures = []
PIN_ARCH = "564aac7f997aab783303a39a161a62417d9abdab19e637ff490083920a0a6add"
PIN_LOG = "d93e084ef3f13802d202577d4c2a843dcef6debbb2ab2a86064fa84473c8fcbb"
SENSITIVE = {"hostkeys.pem", "snapshot.bin", "manifest.txt"}


def sha_of(path):
    try:
        import hashlib
        with open(path, "rb") as fh:
            return hashlib.sha256(fh.read()).hexdigest()
    except OSError:
        return None


def member_bytes(arch):
    with tarfile.open(arch, "r:gz") as tf:
        names = tf.getnames()
        if names.count("crash.mkd") != 1:
            return None
        src = tf.extractfile("crash.mkd")
        return src.read() if src is not None else None


def run_extract(base):
    r = subprocess.run(["bash", "/app/extract.sh", base],
                       capture_output=True, text=True, timeout=120)
    return r.returncode == 0


def check_tree(base, label):
    arch = os.path.join(base, "bundle", "incident.tar.gz")
    log = os.path.join(base, "bundle", "recorder.log")
    out = os.path.join(base, "out", "crash.mkd")

    want = member_bytes(arch)
    if want is None:
        failures.append("%s: bundle archive malformed" % label)
        return
    if not os.path.isfile(out):
        failures.append("%s: missing %s" % (label, out))
        return
    with open(out, "rb") as fh:
        if fh.read() != want:
            failures.append("%s: out/crash.mkd does not match the crash.mkd member" % label)

    # the live log must still
    # contain its LIVE header (the archive member starts with TAPEDUMP).
    try:
        with open(log, "rb") as fh:
            head = fh.readline()
        if head.startswith(b"TAPEDUMP"):
            failures.append("%s: live recorder.log was clobbered by an archive member" % label)
    except OSError:
        failures.append("%s: live recorder.log missing" % label)

    # no non-wanted member materialized anywhere under base
    for root, dirs, files in os.walk(base):
        for f in files:
            if f in SENSITIVE:
                failures.append("%s: sensitive member materialized: %s" % (label, f))
        dirs[:] = [d for d in dirs if d not in ("tests", "solution", "logs")]


# ---------------------------------------------------------------- visible
if not os.path.isfile("/app/extract.sh"):
    failures.append("missing /app/extract.sh (script deliverable)")
else:
    # deliverable left behind by the agent for the visible bundle
    check_tree("/app", "visible")

    # re-execute the deliverable on the visible bundle
    if os.path.exists("/app/out/crash.mkd"):
        os.remove("/app/out/crash.mkd")
    if not run_extract("/app"):
        failures.append("visible: extract.sh execution failed")
    elif not os.path.isfile("/app/out/crash.mkd"):
        failures.append("visible: extract.sh did not write out/crash.mkd")
    else:
        want = member_bytes("/app/bundle/incident.tar.gz")
        with open("/app/out/crash.mkd", "rb") as fh:
            if want is None or fh.read() != want:
                failures.append("visible: re-executed extract.sh output mismatch")
    if sha_of("/app/bundle/incident.tar.gz") != PIN_ARCH:
        failures.append("visible: incident.tar.gz modified by extract.sh")
    if sha_of("/app/bundle/recorder.log") != PIN_LOG:
        failures.append("visible: live recorder.log clobbered by extract.sh")

    # ---------------------------------------------------------------- hidden
    hidden = "/tests/hidden"
    if not os.path.isdir(hidden):
        failures.append("no hidden cases present")
    else:
        n = 0
        for name in sorted(os.listdir(hidden)):
            base = os.path.join(hidden, name)
            if not os.path.isdir(base):
                continue
            n += 1
            with tempfile.TemporaryDirectory(prefix="silt_h_") as tmp:
                wd = os.path.join(tmp, "bundle_case")
                shutil.copytree(base, wd)
                arch_sha = sha_of(os.path.join(wd, "bundle", "incident.tar.gz"))
                log_sha = sha_of(os.path.join(wd, "bundle", "recorder.log"))
                if not run_extract(wd):
                    failures.append("hidden '%s': extract.sh execution failed" % name)
                    continue
                check_tree(wd, "hidden '%s'" % name)
                if sha_of(os.path.join(wd, "bundle", "incident.tar.gz")) != arch_sha:
                    failures.append("hidden '%s': archive modified" % name)
                if sha_of(os.path.join(wd, "bundle", "recorder.log")) != log_sha:
                    failures.append("hidden '%s': live log clobbered" % name)
        if n < 2:
            failures.append("expected >=2 hidden cases, saw %d" % n)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
