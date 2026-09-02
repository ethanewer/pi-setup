#!/bin/bash
# Verifier for larch-vane: EXECUTES the deliverable chain entry point
# (/app/pipeline/publish.sh) on the visible recordings and on hidden
# recording directories, enforces byte-identical pipeline scripts and tree
# listing, and checks the executable bits. Writes reward to
# /logs/verifier/reward.txt. Never crashes on malformed agent output.
set -u
mkdir -p /logs/verifier
reward=0

python3 - <<'PY'
import glob, json, os, re, subprocess, sys

failures = []

def run(cmd, **kw):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=120, **kw)
    except Exception as exc:
        failures.append("running %r raised %s" % (cmd, exc))
        return None

# --- 1. Pipeline scripts must be executable and byte-identical to shipped.
for name in ("ingest.sh", "enrich.sh", "publish.sh"):
    path = "/app/pipeline/%s" % name
    pristine = "/opt/pristine/%s" % name
    if not os.path.isfile(path):
        failures.append("missing %s" % path)
        continue
    if not os.access(path, os.X_OK):
        failures.append("%s lacks the executable bit" % path)
    try:
        with open(path, "rb") as fh:
            got = fh.read()
        with open(pristine, "rb") as fh:
            want = fh.read()
        if got != want:
            failures.append("%s content differs from shipped original" % path)
    except OSError as exc:
        failures.append("cannot read %s: %s" % (path, exc))

# --- 2. Tree listing must be byte-for-byte intact.
LIST_CMD = "cd /app && find pipeline recordings -type f -printf '%p %s\\n' | LC_ALL=C sort"
r = run(["bash", "-c", LIST_CMD])
listing_ok = False
try:
    with open("/app/tree-listing.txt", "rb") as fh:
        shipped = fh.read()
except OSError as exc:
    shipped = None
    failures.append("tree-listing.txt unreadable: %s" % exc)
if r is not None and r.returncode == 0:
    regenerated = (r.stdout or "").encode()
    if shipped is not None:
        if regenerated != shipped:
            failures.append("tree listing no longer byte-for-byte identical")
        else:
            listing_ok = True
else:
    failures.append("listing regeneration command failed")
del listing_ok

# --- Independent recompute of the reduction from RAW logs.
station_re = re.compile(r"[A-Za-z0-9_-]+\Z")
int_re = re.compile(r"-?[0-9]+\Z")

def reduce_raw(src):
    entries, total = [], 0
    for path in sorted(glob.glob(os.path.join(src, "*.log"))):
        readings = []
        try:
            with open(path, "r", encoding="utf-8") as fh:
                lines = fh.read().splitlines()
        except OSError:
            lines = []
        for line in lines:
            parts = line.split(",")
            if len(parts) != 3:
                continue
            st, dep, bat = (p.strip() for p in parts)
            if not station_re.fullmatch(st):
                continue
            if not int_re.fullmatch(dep) or not int_re.fullmatch(bat):
                continue
            readings.append((st, int(dep), int(bat)))
        total += len(readings)
        entries.append({
            "file": os.path.basename(path),
            "readings": len(readings),
            "depth_min": min(d for _, d, _ in readings) if readings else None,
            "depth_max": max(d for _, d, _ in readings) if readings else None,
            "battery_low": min(b for _, _, b in readings) if readings else None,
            "first_station": readings[0][0] if readings else None,
        })
    return {"files": entries, "total_readings": total}

def reports_match(a, b):
    return isinstance(a, dict) and a == b

PUBLISH = "/app/pipeline/publish.sh"

def run_case(src, out):
    if os.path.exists(out):
        os.remove(out)
    return run([PUBLISH, src, out])

def check_output(out_path, want, label):
    try:
        with open(out_path) as fh:
            got = json.load(fh)
    except Exception as exc:
        failures.append("%s output unreadable: %s" % (label, exc))
        return
    if not reports_match(got, want):
        failures.append("%s report mismatch" % label)

# --- 3. Visible case through the deliverable chain.
if os.path.isfile(PUBLISH) and os.access(PUBLISH, os.X_OK):
    r = run_case("/app/recordings", "/tmp/larch_visible_report.json")
    if r is None or r.returncode != 0:
        failures.append("visible publish.sh run failed (exit %s)" % (r.returncode if r else "?"))
    else:
        if "PUBLISH_OK" not in (r.stdout or ""):
            failures.append("visible run missing PUBLISH_OK sentinel")
        check_output("/tmp/larch_visible_report.json", reduce_raw("/app/recordings"), "visible")
else:
    failures.append("publish.sh not executable; cannot run chain")

# --- 4. Report deliverable must equal the visible recompute.
try:
    with open("/app/deployment-report.json") as fh:
        got = json.load(fh)
    if not reports_match(got, reduce_raw("/app/recordings")):
        failures.append("deployment-report.json mismatch")
except Exception as exc:
    failures.append("deployment-report.json unreadable: %s" % exc)

# --- 5. Hidden recording directories through the deliverable chain.
hidden_dir = "/tests/hidden"
if os.path.isdir(hidden_dir):
    cases = sorted(os.listdir(hidden_dir))
    if not cases:
        failures.append("no hidden cases present")
    for case in cases:
        src = os.path.join(hidden_dir, case)
        if not os.path.isdir(src):
            failures.append("hidden '%s' malformed" % case)
            continue
        out = "/tmp/larch_hidden_report.json"
        r = run_case(src, out)
        if r is None or r.returncode != 0:
            failures.append("hidden case '%s' publish failed" % case)
            continue
        check_output(out, reduce_raw(src), "hidden '%s'" % case)
else:
    failures.append("no hidden cases directory")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
