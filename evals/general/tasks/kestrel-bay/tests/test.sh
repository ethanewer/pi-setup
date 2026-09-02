#!/bin/bash
# Verifier for kestrel-bay: checks the visible distributed run, then EXECUTES
# /app/dtrain.py on hidden datasets with hidden worker counts, verifying the
# gloo backend, per-rank markers with exact round-robin shard sizes, and a
# least-squares fit matching an independent serial reference.
# Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

python3 - <<'PY'
import csv, json, math, os, subprocess, sys

PROG = "/app/dtrain.py"
failures = []

def load_json(p):
    with open(p, encoding="utf-8") as fh:
        return json.load(fh)

def serial_fit(csv_path):
    n = sxx = sxy = sx = sy = 0.0
    with open(csv_path, newline="", encoding="utf-8") as fh:
        for row in csv.DictReader(fh):
            x, y = float(row["x"]), float(row["y"])
            n += 1; sx += x; sy += y; sxx += x * x; sxy += x * y
    slope = (n * sxy - sx * sy) / (n * sxx - sx * sx)
    intercept = (sy - slope * sx) / n
    return slope, intercept, int(n)

def shard_sizes(n, world):
    return [len(range(r, n, world)) for r in range(world)]

def run_case(csv_path, outdir, procs, tag):
    subprocess.run(["rm", "-rf", outdir], check=False)
    try:
        r = subprocess.run([sys.executable, PROG, "--data", csv_path,
                            "--out", outdir, "--procs", str(procs)],
                           capture_output=True, text=True, timeout=240)
    except subprocess.TimeoutExpired:
        failures.append("%s: timed out" % tag)
        return
    if r.returncode != 0:
        failures.append("%s: failed rc=%s err=%.400s" % (tag, r.returncode, r.stderr))
        return
    fit_path = os.path.join(outdir, "fit.json")
    if not os.path.isfile(fit_path):
        failures.append("%s: fit.json missing" % tag)
        return
    try:
        fit = load_json(fit_path)
    except Exception as e:
        failures.append("%s: fit.json unreadable: %r" % (tag, e))
        return
    slope, intercept, n = serial_fit(csv_path)
    if int(fit.get("n", -1)) != n:
        failures.append("%s: fit n=%r want %d" % (tag, fit.get("n"), n))
    if int(fit.get("world_size", -1)) != procs:
        failures.append("%s: fit world_size=%r want %d" % (tag, fit.get("world_size"), procs))
    if str(fit.get("backend", "")) != "gloo":
        failures.append("%s: fit backend=%r want 'gloo'" % (tag, fit.get("backend")))
    for key, want in (("slope", slope), ("intercept", intercept)):
        got = fit.get(key)
        if not isinstance(got, (int, float)) or not math.isfinite(got):
            failures.append("%s: fit %s=%r not finite" % (tag, key, got))
        elif abs(got - want) > 1e-4 * max(1.0, abs(want)):
            failures.append("%s: fit %s=%r want %.6f" % (tag, key, got, want))
    # markers
    sizes = shard_sizes(n, procs)
    total_local = 0
    for rk in range(procs):
        mp = os.path.join(outdir, "rank%d.marker" % rk)
        if not os.path.isfile(mp):
            failures.append("%s: marker rank%d missing" % (tag, rk))
            continue
        try:
            m = load_json(mp)
        except Exception as e:
            failures.append("%s: marker rank%d unreadable: %r" % (tag, rk, e))
            continue
        if int(m.get("rank", -1)) != rk or int(m.get("world_size", -1)) != procs:
            failures.append("%s: marker rank%d identity wrong: %r" % (tag, rk, m))
        if str(m.get("backend", "")) != "gloo":
            failures.append("%s: marker rank%d backend=%r" % (tag, rk, m.get("backend")))
        if int(m.get("local_n", -1)) != sizes[rk]:
            failures.append("%s: marker rank%d local_n=%r want %d"
                            % (tag, rk, m.get("local_n"), sizes[rk]))
        total_local += int(m.get("local_n", 0))
    if total_local != n:
        failures.append("%s: sum(local_n)=%d != n=%d" % (tag, total_local, n))

if not os.path.isfile(PROG):
    failures.append("missing /app/dtrain.py")

# visible deliverable
if os.path.isfile("/app/output/fit.json"):
    try:
        fit = load_json("/app/output/fit.json")
        if str(fit.get("backend", "")) != "gloo" or int(fit.get("world_size", -1)) != 4:
            failures.append("visible: fit.json backend/world_size wrong: %r" % fit)
        if not os.path.isfile("/app/output/rank0.marker"):
            failures.append("visible: rank0.marker missing")
    except Exception as e:
        failures.append("visible: fit.json unreadable: %r" % e)
else:
    failures.append("missing /app/output/fit.json")

# hidden cases
hidden_dir = "/tests/hidden"
for case in sorted(os.listdir(hidden_dir)) if os.path.isdir(hidden_dir) else []:
    base = os.path.join(hidden_dir, case)
    csvs = [p for p in sorted(os.listdir(base)) if p.endswith(".csv")] \
        if os.path.isdir(base) else []
    if not csvs:
        failures.append("hidden %r: no csv fixture" % case)
        continue
    # worker count encoded in the case directory name suffix "-<N>"
    try:
        procs = int(case.rsplit("-", 1)[1])
    except Exception:
        failures.append("hidden %r: cannot parse procs from name" % case)
        continue
    run_case(os.path.join(base, csvs[0]), "/tmp/kestrel_%s" % case, procs,
             "hidden/%s" % case)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
