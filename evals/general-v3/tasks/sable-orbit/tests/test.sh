#!/bin/bash
# Verifier for sable-orbit: enforces the no-modify rule on the supplied
# /app/settlement.json, then EXECUTES the deliverable program (/app/solve.py)
# on the visible report and on every hidden case in /tests/hidden, comparing
# output files byte-for-byte. Also checks the visible-case deliverable
# /app/answer.txt. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the supplied visible fixture (the instruction tells the
# agent not to modify it; tampering defeats the visible-case check).
PRISTINE_SHA="db99aa345ed0d23d956485a391dafec305129aec16fe8c3d1fa1f92e02ae6e75"

guard=0
if [ ! -f /app/settlement.json ]; then
    echo "no-modify: /app/settlement.json missing" >&2
    guard=1
else
    actual="$(sha256sum /app/settlement.json | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_SHA" ]; then
        echo "no-modify: /app/settlement.json was modified" >&2
        guard=1
    fi
fi

python3 - "$guard" <<'PY'
import os, subprocess, sys

SOLVE = "/app/solve.py"
guard_broken = int(sys.argv[1])
failures = []

if guard_broken:
    failures.append("visible fixture modified or missing (no-modify rule)")

if not os.path.isfile(SOLVE):
    failures.append("missing /app/solve.py")
else:
    def run_case(report, expected_path):
        out = "/tmp/sable_orbit_out.txt"
        if os.path.exists(out):
            os.remove(out)
        try:
            r = subprocess.run(
                [sys.executable, SOLVE, report, out],
                capture_output=True, text=True, timeout=60,
            )
        except Exception as e:
            return "exec failed: %s" % e
        if r.returncode != 0:
            return "nonzero exit"
        if not os.path.isfile(out):
            return "no output file"
        with open(out, "rb") as fh:
            got = fh.read()
        with open(expected_path, "rb") as fh:
            want = fh.read()
        if got != want:
            return "output %r != expected %r" % (got, want)
        # stdout must carry the same integer
        digits = want.decode().rstrip("\n")
        if r.stdout.strip() != digits:
            return "stdout %r != %r" % (r.stdout.strip(), digits)
        return None

    # --- visible case: EXECUTE solve.py on the live supplied fixture ---
    err = run_case("/app/settlement.json", "/tests/expected/visible.txt")
    if err:
        failures.append("visible case failed: %s" % err)

    # --- visible-case deliverable: /app/answer.txt must match exactly ---
    if not os.path.isfile("/app/answer.txt"):
        failures.append("missing /app/answer.txt")
    else:
        with open("/app/answer.txt", "rb") as fh:
            got = fh.read()
        with open("/tests/expected/visible.txt", "rb") as fh:
            want = fh.read()
        if got != want:
            failures.append("answer.txt %r != expected %r" % (got, want))

    # --- hidden cases: genuinely distinct reports with their own expecteds ---
    hidden_dir = "/tests/hidden"
    cases = sorted(d for d in os.listdir(hidden_dir)
                   if os.path.isdir(os.path.join(hidden_dir, d)))
    if not cases:
        failures.append("no hidden cases present")
    for c in cases:
        base = os.path.join(hidden_dir, c)
        report = os.path.join(base, "report.json")
        exp = os.path.join(base, "expected.txt")
        if not (os.path.isfile(report) and os.path.isfile(exp)):
            failures.append("hidden '%s' malformed" % c)
            continue
        err = run_case(report, exp)
        if err:
            failures.append("hidden case '%s' failed: %s" % (c, err))

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
