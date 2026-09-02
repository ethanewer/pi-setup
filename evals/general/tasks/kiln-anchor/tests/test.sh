#!/bin/bash
# Verifier for kiln-anchor: EXECUTES the deliverables — /app/dist/kilnstat on
# visible + hidden logs (also bare-name via PATH, and a fresh cc rebuild of
# /app/src/kilnstat.c) — against an independent recomputation of the six-line
# summary. Writes reward to /logs/verifier/reward.txt. Never crashes on
# malformed agent output.
set -u
mkdir -p /logs/verifier
reward=0

python3 - <<'PY'
import glob, os, re, subprocess, sys

failures = []

def run(cmd, **kw):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=60, **kw)
    except Exception as exc:
        failures.append("running %r raised %s" % (cmd, exc))
        return None

TIME_RE = re.compile(r"([01][0-9]|2[0-3]):[0-5][0-9]\Z")
NUM_RE = re.compile(r"[+-]?([0-9]+(\.[0-9]*)?|\.[0-9]+)([eE][+-]?[0-9]+)?\Z")

def summarize(path):
    n = malformed = 0
    mn = mx = None
    total = 0.0
    with open(path) as fh:
        for raw in fh:
            stripped = raw.strip()
            if stripped == "" or stripped.startswith("#"):
                continue
            toks = raw.split()
            if len(toks) == 2 and TIME_RE.fullmatch(toks[0]) and NUM_RE.fullmatch(toks[1]):
                v = float(toks[1])
                if n == 0:
                    mn = mx = v
                else:
                    mn = min(mn, v)
                    mx = max(mx, v)
                total += v
                n += 1
            else:
                malformed += 1
    lines = ["samples=%d" % n]
    if n > 0:
        mean = total / n
        lines += ["min=%.3f" % mn, "max=%.3f" % mx,
                  "mean=%.3f" % mean, "range=%.3f" % (mx - mn)]
    else:
        lines += ["min=NA", "max=NA", "mean=NA", "range=NA"]
    lines.append("malformed=%d" % malformed)
    return "\n".join(lines) + "\n"

def check_binary(binpath, logpath, label, cwd=None):
    r = run([binpath, logpath], cwd=cwd)
    if r is None or r.returncode != 0:
        failures.append("%s run failed (exit %s)" % (label, r.returncode if r else "?"))
        return
    want = summarize(logpath)
    got = r.stdout or ""
    if got.splitlines() != want.splitlines():
        failures.append("%s output mismatch on %s" % (label, logpath))

DIST = "/app/dist/kilnstat"
SRC = "/app/src/kilnstat.c"
VISIBLE = "/app/data/shift-07.log"

# --- 0. Deliverables exist.
if not os.path.isfile(SRC):
    failures.append("missing /app/src/kilnstat.c")
if not os.path.isfile(DIST):
    failures.append("missing /app/dist/kilnstat")

# --- 1. Bare-name PATH resolution in a non-login shell from a scratch cwd.
r = run(["sh", "-c", "cd /tmp && command -v kilnstat"])
if r is None or r.returncode != 0 or not (r.stdout or "").strip():
    failures.append("bare-name 'kilnstat' does not resolve on PATH from /tmp")

# --- 2. Fresh rebuild of the source deliverable must work.
rebuilt = "/tmp/kilnstat_rebuild"
if os.path.isfile(rebuilt):
    os.remove(rebuilt)
if os.path.isfile(SRC):
    r = run(["cc", "-std=c11", "-O2", "-o", rebuilt, SRC, "-lm"])
    if r is None or r.returncode != 0:
        failures.append("cc rebuild of /app/src/kilnstat.c failed")
        rebuilt = None
else:
    rebuilt = None

# --- 3. Visible case: deliverable binary (directly and bare-name from /tmp).
if os.path.isfile(DIST) and os.path.isfile(VISIBLE):
    check_binary(DIST, VISIBLE, "dist binary (visible)")
    check_binary("kilnstat", VISIBLE, "bare-name (visible)", cwd="/tmp")
    if rebuilt:
        check_binary(rebuilt, VISIBLE, "rebuilt binary (visible)")
else:
    failures.append("visible case skipped (missing binary or data)")

# --- 4. Hidden cases.
hidden_dir = "/tests/hidden"
if os.path.isdir(hidden_dir):
    cases = sorted(glob.glob(os.path.join(hidden_dir, "*", "series.log")))
    if not cases:
        failures.append("no hidden cases present")
    for logpath in cases:
        label = "hidden '%s'" % os.path.basename(os.path.dirname(logpath))
        if os.path.isfile(DIST):
            check_binary(DIST, logpath, label)
        if rebuilt:
            check_binary(rebuilt, logpath, label + " (rebuilt)")
else:
    failures.append("no hidden cases directory")

# --- 5. Usage and missing-file behavior (deliverable binary).
if os.path.isfile(DIST):
    r = run([DIST])
    if r is None or r.returncode != 2 or "usage: kilnstat" not in (r.stderr or ""):
        failures.append("no-arg usage contract violated")
    r = run([DIST, "/nonexistent/kiln_anchor_file.log"])
    if r is None or r.returncode != 1 or (r.stdout or ""):
        failures.append("missing-file contract violated")
    r = run([DIST, VISIBLE, VISIBLE])
    if r is None or r.returncode != 2:
        failures.append("extra-arg usage contract violated")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
