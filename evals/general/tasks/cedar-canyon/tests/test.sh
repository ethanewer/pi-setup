#!/bin/bash
# Verifier for cedar-canyon (executes-deliverable).
# Re-invokes /app/solve.py on the default workbench fixture and on every hidden
# fixture, and independently re-checks: maximal-square (via import solve),
# the native prefix-sum binding, the serial-vs-OpenMP sim (exact agreement,
# genuine motion, and a speedup window on the BENCHMARK fixture), and the
# per-translation-unit LLVM IR. Writes a numeric reward to
# /logs/verifier/reward.txt; must pass only when a real stack + honest driver
# exist.
set -u
mkdir -p /logs/verifier

[ -f /app/solve.py ] || { echo "missing /app/solve.py" >&2; echo "0" > /logs/verifier/reward.txt; exit 0; }
[ -f /app/answer.json ] || { echo "missing /app/answer.json" >&2; echo "0" > /logs/verifier/reward.txt; exit 0; }

python3 - <<'PY'
import ctypes
import json
import math
import os
import shutil
import subprocess
import sys
import importlib.util

FAILS = []

def run(cmd, **kw):
    env = dict(os.environ)
    env["OMP_NUM_THREADS"] = "2"  # container is cpus=2; avoid oversubscription
    kw.setdefault("env", env)
    return subprocess.run(cmd, capture_output=True, text=True, **kw)

# ---------------- independent references ----------------
def ref_maximal_square(rows):
    if not rows:
        return 0
    width = min((len(r) for r in rows), default=0)
    if width == 0:
        return 0
    best = 0
    dp = [[0] * width for _ in rows]
    for i, r in enumerate(rows):
        for j in range(width):
            v = 1 if r[j] in ("1", 1, True) else 0
            if not v:
                dp[i][j] = 0
                continue
            dp[i][j] = 1 if (i == 0 or j == 0) else \
                min(dp[i-1][j], dp[i][j-1], dp[i-1][j-1]) + 1
            best = max(best, dp[i][j])
    return best * best

def ref_prefix(vals):
    out, acc = [], 0.0
    for v in vals:
        acc += v
        out.append(acc)
    return out

def read_values(p):
    if not os.path.exists(p):
        return []
    out = []
    with open(p) as fh:
        for line in fh:
            s = line.strip()
            if s:
                try:
                    out.append(float(s))
                except ValueError:
                    pass
    return out

def read_grid(p):
    if not os.path.exists(p):
        return []
    rows = []
    with open(p) as fh:
        for line in fh:
            rows.append(line.rstrip("\n"))
    return rows

def read_sim(fixture):
    d = {"N": 40000, "STEPS": 20, "SEED": 7, "BENCHMARK": False}
    p = os.path.join(fixture, "sim.ini")
    if os.path.exists(p):
        with open(p) as fh:
            for line in fh:
                s = line.strip()
                if not s or s.startswith("#") or "=" not in s:
                    continue
                k, v = [x.strip() for x in s.split("=", 1)]
                if k in ("N", "STEPS", "SEED"):
                    try:
                        d[k] = int(v)
                    except ValueError:
                        pass
                elif k == "BENCHMARK":
                    d["BENCHMARK"] = v.strip() == "1"
    return d

# ---- A. import solve (capability must be importable without building) ----
try:
    spec = importlib.util.spec_from_file_location("solve", "/app/solve.py")
    solve = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(solve)
except Exception as e:
    FAILS.append("cannot import solve: " + str(e))

# ---- B. re-run default driver (reproducibility) ----
r = run(["python3", "/app/solve.py"])
if r.returncode != 0:
    FAILS.append("default solve.py failed: " + (r.stderr or r.stdout)[-400:])
elif not os.path.exists("/app/answer.json"):
    FAILS.append("no answer.json after default run")

# ---- C. per-translation-unit LLVM IR exists (independently emit once) ----
if not os.path.exists("/app/math/build-emit/CMakeCache.txt"):
    run(["cmake", "-S", "/app/math", "-B", "/app/math/build-emit"])
r = run(["cmake", "--build", "/app/math/build-emit", "--target", "ir"])
tu_units = ["sim.c.ll", "natc.c.ll", "picker.c.ll", "port.cpp.ll"]
for f in tu_units:
    fp = os.path.join("/app/math/build-emit/ir", f)
    if not (os.path.exists(fp) and os.path.getsize(fp) > 0):
        FAILS.append("missing LLVM IR translation unit: " + f)

# ---- D. hidden case driver runs + independent correctness ----
H = "/tests/hidden"
cases = sorted(d for d in os.listdir(H) if os.path.isdir(os.path.join(H, d)))
if len(cases) < 3:
    FAILS.append("need at least 3 hidden cases")

tvd = 0  # distance aggregate for binding
for c in cases:
    src = os.path.join(H, c)
    tmp = "/tmp/case_" + c
    shutil.rmtree(tmp, ignore_errors=True)
    shutil.copytree(src, tmp)

    r = run(["python3", "/app/solve.py", "run", tmp])
    if r.returncode != 0:
        FAILS.append("%s: solve run crashed: %s" % (c, (r.stderr or r.stdout)[-300:]))
        continue
    try:
        ans = json.load(open("/app/answer.json"))
    except Exception as e:
        FAILS.append("%s: answer.json unreadable: %s" % (c, e))
        continue

    # 1) maximal-square: exact area and importable capability
    grid = read_grid(os.path.join(src, "grid.txt"))
    exp = ref_maximal_square(grid)
    got_mod = solve.maximal_square(grid) if "solve" in dir() else None
    if ans.get("max_square") != exp:
        FAILS.append("%s: max_square %r != %r" % (c, ans.get("max_square"), exp))
    if got_mod is None or got_mod != exp:
        FAILS.append("%s: solve.maximal_square %r != %r" % (c, got_mod, exp))

    # 2) native binding prefix-sum == reference
    vals = read_values(os.path.join(src, "values.txt"))
    outa = solve.binding_prefix(vals)
    ref = ref_prefix(vals)
    if len(outa) != len(ref):
        FAILS.append("%s: binding length %d != %d" % (c, len(outa), len(ref)))
    else:
        for i, (g, e) in enumerate(zip(outa, ref)):
            if not (g == e or (g and e and abs(g - e) <= 1e-6 * max(1.0, abs(e)))):
                FAILS.append("%s: binding[%d] %r != %r" % (c, i, g, e))
                break

    # 3) sim: exact checksum agreement + genuine motion on every case
    sim = read_sim(src)
    sbin = "/app/math/bin/sim_serial"
    obin = "/app/math/bin/sim_openmp"
    if not (os.path.exists(sbin) and os.path.exists(obin)):
        FAILS.append("%s: sim binaries missing" % c)
        continue
    ds = run([sbin, str(sim["N"]), str(sim["STEPS"]), str(sim["SEED"]), tmp + "/s.csv"])
    do = run([obin, str(sim["N"]), str(sim["STEPS"]), str(sim["SEED"]), tmp + "/o.csv"])
    def parse(o):
        d = {"t": None, "move": None, "sum": None}
        for line in o.stdout.splitlines():
            if line.startswith("TIME"): d["t"] = float(line.split()[1])
            elif line.startswith("MOVE"): d["move"] = float(line.split()[1])
            elif line.startswith("SUM"): d["sum"] = line.split()[1].strip()
        return d
    ps, po = parse(ds), parse(do)
    if not (ps["sum"] and po["sum"]):
        FAILS.append("%s: sim did not report checksum" % c)
        continue
    if ps["sum"] != po["sum"]:
        FAILS.append("%s: serial/openmp checksum mismatch %s vs %s" % (c, ps["sum"], po["sum"]))
    if not (ps["move"] and po["move"]):
        FAILS.append("%s: sim reported no motion" % c)
    elif po["move"] <= 1e-6:
        FAILS.append("%s: genuine motion missing (move %r)" % (c, po["move"]))

    # speedup enforced ONLY on the BENCHMARK=1 fixture
    if sim["BENCHMARK"]:
        def med(bin_, cfile):
            ts = []
            for _ in range(3):
                o = run([bin_, str(sim["N"]), str(sim["STEPS"]), str(sim["SEED"]), cfile])
                for line in o.stdout.splitlines():
                    if line.startswith("TIME"):
                        ts.append(float(line.split()[1]))
                        break
            ts.sort()
            return ts[len(ts)//2]
        st = med(sbin, tmp + "/sc.csv")
        pt = med(obin, tmp + "/o.csv")
        if not (st and pt and st > 0 and pt > 0):
            FAILS.append("%s: sim timing unavailable" % c)
        elif st < 0.05:
            FAILS.append("%s: serial sim time implausibly small %r" % (c, st))
        else:
            sup = st / pt
            if not (1.10 <= sup <= 6.0):
                FAILS.append("%s: independent speedup %.3f out of window" % (c, sup))
            # cross-check the driver's honest report
            if ans.get("speedup") is None:
                FAILS.append("%s: driver did not report a speedup" % c)
            elif sup > 0 and abs(ans["speedup"] - sup) / sup > 0.40:
                FAILS.append("%s: driver speedup %.3f disagrees with %.3f" % (c, ans["speedup"], sup))

    # answer.json structural contract
    for k in ("serial_s", "parallel_s", "speedup", "move", "positions_match",
              "max_square", "binding_prefix", "llvm_ir", "ok"):
        if k not in ans:
            FAILS.append("%s: answer.json missing key %s" % (c, k))
    # llvm_ir paths should exist
    for f in ans.get("llvm_ir", []):
        if not (os.path.exists(f) and os.path.getsize(f) > 0):
            FAILS.append("%s: reported llvm_ir missing: %s" % (c, f))

    # binding exactness (accumulate across cases)
    if vals:
        tvd = max(tvd, max(abs(g) for g in outa))

if FAILS:
    print("FAILURES:")
    for m in FAILS:
        print("  - " + m)
    open("/logs/verifier/reward.txt", "w").write("0")
    sys.exit(0)

print("ALL PASS (%d hidden cases)" % len(cases))
open("/logs/verifier/reward.txt", "w").write("1")
sys.exit(0)
PY