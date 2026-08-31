#!/bin/bash
# Verifier for amber-quarry: checks the visible deliverable, ENFORCES the
# no-modify rule on /app/case, and EXECUTES /app/verdict_scan.py on the visible
# and hidden transcript directories. Writes REWARD (0/1) to
# /logs/verifier/reward.txt. Never crashes on malformed agent output.
set -u

mkdir -p /logs/verifier
reward=0

PRISTINE_COMBINED_SHA="63805b1630e3801ecc53e21eaef32e88fec791652516fc6e6d39bc1ea95da7c3"
export PRISTINE_COMBINED_SHA

python3 - <<'PY'
import hashlib, os, subprocess, sys

SOLVE = "/app/verdict_scan.py"
failures = []


def combined_sha(d):
    """sha256 over sorted 'name:filesha' lines of *.log files under dir d."""
    names = sorted(
        n for n in os.listdir(d)
        if n.endswith(".log") and os.path.isfile(os.path.join(d, n))
    )
    h = hashlib.sha256()
    for n in names:
        fs = hashlib.sha256(open(os.path.join(d, n), "rb").read()).hexdigest()
        h.update(("%s:%s\n" % (n, fs)).encode())
    return h.hexdigest()


def norm(text):
    lines = [ln.rstrip("\r") for ln in text.replace("\r\n", "\n").split("\n")]
    while lines and lines[-1] == "":
        lines.pop()
    return "\n".join(lines)


def run_case(log_dir, expected_path):
    out = "/tmp/aq_out.txt"
    if os.path.exists(out):
        os.remove(out)
    try:
        r = subprocess.run([sys.executable, SOLVE, log_dir, out],
                           capture_output=True, text=True, timeout=120)
    except Exception as e:
        failures.append("run crashed on %s: %r" % (log_dir, e))
        return
    if r.returncode != 0:
        failures.append("scan exited %d on %s" % (r.returncode, log_dir))
        return
    if not os.path.exists(out):
        failures.append("no output file for %s" % log_dir)
        return
    try:
        got = norm(open(out).read())
        want = norm(open(expected_path).read())
        if got != want:
            failures.append("report mismatch for %s" % log_dir)
    except Exception as e:
        failures.append("unreadable output for %s: %r" % (log_dir, e))


if not os.path.isfile(SOLVE):
    failures.append("missing /app/verdict_scan.py")
else:
    # no-modify check on the visible transcripts
    if os.path.isdir("/app/case/logs"):
        actual = combined_sha("/app/case/logs")
        if actual != os.environ.get("PRISTINE_COMBINED_SHA", ""):
            failures.append("visible transcripts modified (no-modify rule)")
        # visible case: re-run the deliverable and compare
        run_case("/app/case/logs", "/tests/expected_visible.txt")
        # visible-case deliverable must match too
        try:
            got = norm(open("/app/verdicts_report.txt").read())
            want = norm(open("/tests/expected_visible.txt").read())
            if got != want:
                failures.append("/app/verdicts_report.txt does not match visible expected")
        except Exception as e:
            failures.append("/app/verdicts_report.txt unreadable: %r" % e)
    else:
        failures.append("visible transcripts missing")

    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            logs = os.path.join(base, "logs")
            exp = os.path.join(base, "expected.txt")
            if not (os.path.isdir(logs) and os.path.isfile(exp)):
                failures.append("hidden case '%s' malformed" % c)
                continue
            run_case(logs, exp)
    else:
        failures.append("no hidden cases dir")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
