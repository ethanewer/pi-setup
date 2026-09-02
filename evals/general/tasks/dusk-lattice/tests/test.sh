#!/bin/bash
# Verifier for dusk-lattice. Executes the deliverable /app/reimpl.py on the
# visible fixture and on every hidden case, comparing stdout byte-for-byte
# with reference outputs produced by the native binary. The native target is
# temporarily moved aside so the deliverable cannot delegate to it. Checks
# /app/notes.md exists and is substantive, and that the visible fixture was
# not tampered with. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
reward=0

PRISTINE_FIXTURE_SHA="09b1daea6b2eafc6c105e2115b31ddaa0e372a27218724245ec8cfdaed6d035e"

# Hide the native target during grading: reimpl.py must stand alone.
hid_native=0
if [ -f /app/target/pixelcast ]; then
    mv /app/target/pixelcast /app/target/.pixelcast.hidden
    hid_native=1
fi
restore_native() {
    if [ "$hid_native" -eq 1 ]; then
        mv /app/target/.pixelcast.hidden /app/target/pixelcast 2>/dev/null
    fi
}
trap restore_native EXIT

export PRISTINE_FIXTURE_SHA
python3 - <<'PY'
import hashlib, os, subprocess, sys

SOLVE = "/app/reimpl.py"
failures = []

# no-modify guard on the visible fixture
sha = ""
try:
    with open("/app/fixture.ppm", "rb") as fh:
        sha = hashlib.sha256(fh.read()).hexdigest()
except OSError:
    pass
if sha != os.environ["PRISTINE_FIXTURE_SHA"]:
    failures.append("visible fixture /app/fixture.ppm missing or modified")

# deliverable program exists and does not delegate to the native binary
if not os.path.isfile(SOLVE):
    failures.append("missing /app/reimpl.py")
else:
    try:
        src = open(SOLVE, encoding="utf-8", errors="replace").read()
        if "/app/target" in src:
            failures.append("reimpl.py references the native target")
    except OSError:
        failures.append("reimpl.py unreadable")

# notes deliverable
try:
    notes = open("/app/notes.md", encoding="utf-8", errors="replace").read()
    if len(notes.strip()) < 200:
        failures.append("notes.md too thin (must document findings)")
except OSError:
    failures.append("missing /app/notes.md")


def run_case(inp, expected_path):
    """Run the deliverable on inp; byte-compare stdout to expected file."""
    r = subprocess.run([sys.executable, SOLVE, inp],
                       capture_output=True, timeout=120)
    if r.returncode != 0:
        return False, "rc=%d stderr=%s" % (r.returncode,
                                           r.stderr.decode()[-120:])
    try:
        with open(expected_path, "rb") as fh:
            want = fh.read()
    except OSError as e:
        return False, "unreadable expected: %s" % e
    if r.stdout != want:
        return False, "stdout differs (%d vs %d bytes)" % (
            len(r.stdout), len(want))
    return True, ""


if os.path.isfile(SOLVE) and not failures:
    ok, why = run_case("/app/fixture.ppm", "/tests/expected_visible.ppm")
    if not ok:
        failures.append("visible case failed: " + why)

    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(d for d in os.listdir(hidden_dir)
                       if os.path.isdir(os.path.join(hidden_dir, d)))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            inp = os.path.join(hidden_dir, c, "input.ppm")
            exp = os.path.join(hidden_dir, c, "expected.ppm")
            if not (os.path.isfile(inp) and os.path.isfile(exp)):
                failures.append("hidden '%s' malformed" % c)
                continue
            ok, why = run_case(inp, exp)
            if not ok:
                failures.append("hidden case '%s' failed: %s" % (c, why))
    else:
        failures.append("no hidden cases directory")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
