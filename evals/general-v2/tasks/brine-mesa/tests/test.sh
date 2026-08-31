#!/bin/bash
# Verifier for brine-mesa: runs the deliverable binaries on the visible fixture
# and on every hidden fixture, compares positions/moved against reference data,
# enforces the serial-vs-OpenMP agreement, genuine motion, real OpenMP linkage,
# and the O(n) runtime on the large fixture, and cross-checks report.json.
# Writes 1 or 0 to /logs/verifier/reward.txt; guards every parse.
set -u

mkdir -p /logs/verifier
reward=0

python3 - <<'PY'
import hashlib, json, math, os, re, subprocess, sys

fails = []

PRISTINE_SHA = "7309391ea571c623ef2e3163c2f886971d23e238b36c0cdd564e280de032bf42"

def sha(p):
    try:
        return hashlib.sha256(open(p, "rb").read()).hexdigest()
    except OSError:
        return None

if sha("/app/fixture_main.txt") != PRISTINE_SHA:
    fails.append("/app/fixture_main.txt missing or modified")

def read_header(path):
    with open(path) as fh:
        first = fh.readline().split()
    if len(first) != 7:
        raise ValueError("bad header")
    n = int(first[0])
    return n, float(first[1]), float(first[2]), int(first[3]), (float(first[4]),
                                                               float(first[5]), float(first[6]))

def read_positions(path):
    out = []
    with open(path) as fh:
        for line in fh:
            t = line.split()
            if len(t) == 3:
                out.append((float(t[0]), float(t[1]), float(t[2])))
    return out

def min_image(a, b, L):
    d = a - b
    d -= L * round(d / L)
    return d

def positions_ok(got, want, Ls, atol=1e-6):
    if len(got) != len(want):
        return False
    maxdev = 0.0
    for (gx, gy, gz), (wx, wy, wz) in zip(got, want):
        dx = min_image(gx, wx, Ls[0]); dy = min_image(gy, wy, Ls[1]); dz = min_image(gz, wz, Ls[2])
        dev = math.sqrt(dx * dx + dy * dy + dz * dz)
        if dev > maxdev:
            maxdev = dev
        if dev > atol:
            return False
    return True

LINE_RE = re.compile(r"^threads=(\d+) seconds=([0-9.]+) moved=([0-9.eE+\-]+)$")

def run_binary(binary, inp, outpos, timeout=90):
    if os.path.exists(outpos):
        os.remove(outpos)
    try:
        r = subprocess.run([binary, inp, outpos], capture_output=True,
                           text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return None, None, "timeout after %ds" % timeout
    if r.returncode != 0:
        return None, None, "rc=%d %s" % (r.returncode, (r.stderr or "")[-200:])
    m = LINE_RE.match((r.stdout or "").strip().splitlines()[-1]
                      if (r.stdout or "").strip() else "")
    if not m:
        return None, None, "bad stdout: %r" % ((r.stdout or "")[-120:])
    try:
        pos = read_positions(outpos)
    except Exception as e:
        return None, None, "positions unreadable: %s" % e
    return {"threads": int(m.group(1)), "seconds": float(m.group(2)),
            "moved": float(m.group(3))}, pos, None

# --- OpenMP linkage inspection ---------------------------------------------
omp_ok = False
try:
    r = subprocess.run(["ldd", "/app/drift_omp"], capture_output=True, text=True)
    if "libgomp" in (r.stdout or ""):
        omp_ok = True
except Exception:
    pass
if not omp_ok:
    try:
        r = subprocess.run(["nm", "-D", "/app/drift_omp"], capture_output=True, text=True)
        omp_ok = "GOMP_parallel" in (r.stdout or "")
    except Exception:
        pass
if not omp_ok:
    try:
        r = subprocess.run(["strings", "/app/drift_omp"], capture_output=True, text=True)
        omp_ok = "GOMP_parallel" in (r.stdout or "")
    except Exception:
        pass
if not omp_ok:
    fails.append("drift_omp shows no OpenMP linkage (libgomp/GOMP_parallel)")

observed = {}

def check_fixture(inp, exp_pos, exp_summary, label, expect_speedup=False):
    try:
        n, cutoff, dt, steps, Ls = read_header(inp)
        want_pos = read_positions(exp_pos)
        want_moved = float(json.load(open(exp_summary))["moved"])
    except Exception as e:
        fails.append("%s: reference data unreadable: %s" % (label, e))
        return
    s, spos, err = run_binary("/app/drift_serial", inp, "/tmp/bm_serial_pos.txt")
    if err:
        fails.append("%s: serial failed: %s" % (label, err)); return
    if s["threads"] != 1:
        fails.append("%s: serial threads=%d (want 1)" % (label, s["threads"]))
    if not positions_ok(spos, want_pos, Ls):
        fails.append("%s: serial positions deviate from reference" % label)
    if abs(s["moved"] - want_moved) > 1e-6:
        fails.append("%s: serial moved %.6f vs reference %.6f" % (label, s["moved"], want_moved))
    if s["moved"] <= 1e-3:
        fails.append("%s: no genuine motion (moved=%.6f)" % (label, s["moved"]))
    o, opos, err = run_binary("/app/drift_omp", inp, "/tmp/bm_omp_pos.txt")
    if err:
        fails.append("%s: omp failed: %s" % (label, err)); return
    if o["threads"] < 2:
        fails.append("%s: omp threads=%d (want >=2)" % (label, o["threads"]))
    if not positions_ok(opos, spos, Ls, atol=0.0):
        fails.append("%s: omp positions do not exactly match serial" % label)
    if abs(o["moved"] - s["moved"]) > 1e-9:
        fails.append("%s: omp moved != serial moved" % label)
    observed[label] = (s, o)
    if expect_speedup and not (o["seconds"] < s["seconds"]):
        fails.append("%s: omp (%.3fs) not faster than serial (%.3fs)"
                     % (label, o["seconds"], s["seconds"]))

# visible fixture
check_fixture("/app/fixture_main.txt",
              "/tests/expected_positions_fixture_main.txt",
              "/tests/expected_summary.json", "visible")

# hidden fixtures
hdir = "/tests/hidden"
cases = sorted(d for d in os.listdir(hdir)
               if os.path.isdir(os.path.join(hdir, d))) if os.path.isdir(hdir) else []
if len(cases) < 2:
    fails.append("expected >=2 hidden cases, found %d" % len(cases))
for c in cases:
    base = os.path.join(hdir, c)
    if not all(os.path.isfile(os.path.join(base, f)) for f in
               ("input.txt", "expected_positions.txt", "expected_summary.json")):
        fails.append("hidden '%s' malformed" % c)
        continue
    check_fixture(os.path.join(base, "input.txt"),
                  os.path.join(base, "expected_positions.txt"),
                  os.path.join(base, "expected_summary.json"),
                  c, expect_speedup=(c == "embankment"))

# report.json cross-check
try:
    rep = json.load(open("/app/report.json"))
    assert isinstance(rep, dict)
    for k in ("serial", "omp", "positions_match", "ok"):
        assert k in rep, k
    if rep["positions_match"] is not True or rep["ok"] is not True:
        fails.append("report.json positions_match/ok not true")
    vis = observed.get("visible")
    if vis and isinstance(rep["serial"], dict) and isinstance(rep["omp"], dict):
        if abs(float(rep["serial"]["moved"]) - vis[0]["moved"]) > 1e-6:
            fails.append("report.json serial.moved inconsistent with observed run")
        if abs(float(rep["omp"]["moved"]) - vis[1]["moved"]) > 1e-6:
            fails.append("report.json omp.moved inconsistent with observed run")
        if int(rep["omp"]["threads"]) != vis[1]["threads"]:
            fails.append("report.json omp.threads inconsistent with observed run")
except Exception as e:
    fails.append("report.json unreadable or wrong schema: %s" % e)

print("verify failures:", fails)
sys.exit(1 if fails else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
