#!/usr/bin/env bash
# crane-anvil verifier: force-rebuilds via the agent's /app/Makefile (must drive
# gfortran with module-before-program ordering), then executes the deliverable
# /app/avalanche_report on the visible data and two hidden station files.
# Writes 1/0 to /logs/verifier/reward.txt; never crashes on missing output.
set -u
mkdir -p /logs/verifier
reward=0

python3 - <<'PY'
import json, os, re, subprocess, sys

failures = []
MAKEFILE = "/app/Makefile"
BIN = "/app/avalanche_report"


def parse_out(text):
    """Parse the four documented lines; returns dict or None."""
    got = {}
    for line in text.strip().splitlines():
        m = re.match(r"^(n|warm|mean|peak)\s*=\s*(\S.*)$", line.strip())
        if not m:
            return None
        got[m.group(1)] = m.group(2).strip()
    if set(got) != {"n", "warm", "mean", "peak"}:
        return None
    return got


def compute(path, thresh):
    with open(path) as fh:
        lines = [l for l in fh.read().splitlines() if l.strip()
                 and not l.startswith("#")]
    n = int(lines[0].split()[0])
    vals = [float(x) for x in lines[1].split()]
    assert len(vals) == n
    warm = sum(1 for v in vals if v > thresh)
    mean = sum(vals) / n
    peak = max(vals)
    return {"n": n, "warm": warm, "mean": mean, "peak": peak}


def check_case(data, thresh, tag):
    r = subprocess.run([BIN, data, str(thresh)],
                       capture_output=True, text=True, timeout=60)
    if r.returncode != 0:
        failures.append("%s: exit %d stderr=%r" % (tag, r.returncode,
                                                   r.stderr[:200]))
        return
    got = parse_out(r.stdout)
    if got is None:
        failures.append("%s: output does not match the documented four lines: %r"
                        % (tag, r.stdout))
        return
    want = compute(data, float(thresh))
    try:
        if int(got["n"]) != want["n"]:
            failures.append("%s: n %s != %s" % (tag, got["n"], want["n"]))
        if int(got["warm"]) != want["warm"]:
            failures.append("%s: warm %s != %s" % (tag, got["warm"],
                                                   want["warm"]))
        if abs(float(got["mean"]) - want["mean"]) > 0.0051:
            failures.append("%s: mean %s != %s" % (tag, got["mean"],
                                                   want["mean"]))
        if abs(float(got["peak"]) - want["peak"]) > 0.0051:
            failures.append("%s: peak %s != %s" % (tag, got["peak"],
                                                   want["peak"]))
    except ValueError as exc:
        failures.append("%s: unparsable numeric field: %r" % (tag, exc))


# --- 1. deliverables exist ---
if not os.path.isfile(MAKEFILE):
    failures.append("missing /app/Makefile")
if not os.path.isfile(BIN):
    failures.append("missing /app/avalanche_report")

# --- 2. forced full rebuild; gfortran must appear; ordering must work ---
if os.path.isfile(MAKEFILE):
    try:
        r = subprocess.run(["make", "-B", "-f", "Makefile"],
                           cwd="/app", capture_output=True, text=True,
                           timeout=240)
        log = r.stdout + r.stderr
        if r.returncode != 0:
            failures.append("make -B failed rc=%d: %s"
                            % (r.returncode, r.stderr[-400:]))
        if "gfortran" not in log:
            failures.append("compile log does not show the gfortran frontend")
        if not os.path.isfile(BIN):
            failures.append("rebuild did not produce /app/avalanche_report")
    except Exception as exc:
        failures.append("make crashed: %r" % exc)

# --- 3. visible case ---
if os.path.isfile(BIN):
    check_case("/app/data/ridgeline.dat", "2.0", "visible")

# --- 4. hidden cases ---
for tag, d in (("hidden-alpine", "/tests/hidden/alpine"),
               ("hidden-summit", "/tests/hidden/summit")):
    data = os.path.join(d, "data.dat")
    tf = os.path.join(d, "threshold.txt")
    if not (os.path.isfile(data) and os.path.isfile(tf) and os.path.isfile(BIN)):
        failures.append("%s: inputs missing" % tag)
        continue
    thresh = open(tf).read().strip()
    check_case(data, thresh, tag)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
