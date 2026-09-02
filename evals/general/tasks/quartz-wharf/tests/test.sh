#!/usr/bin/env bash
# Verifier for quartz-wharf scientific-compute toolbox.
set -u
mkdir -p /logs/verifier
reward=0
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

python3 - "$work" <<'PY'
import os, glob, json, time, subprocess, sys
import numpy as np
import importlib.util
from scipy.integrate import solve_ivp

reward = 1

def write_reward():
    with open("/logs/verifier/reward.txt", "w") as f:
        f.write(str(reward))

def fail(msg):
    global reward
    reward = 0
    print("FAIL: " + msg, file=sys.stderr)

def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

if not all(os.path.exists(p) for p in
           ["/app/integrate.py", "/app/eig.py", "/app/bench.py"]):
    fail("one or more /app deliverables missing")
    print("REWARD=%d" % reward)
    write_reward()
    sys.exit(0)

integ = load("/app/integrate.py", "integrate_deliver")
eig   = load("/app/eig.py", "eig_deliver")
BPATH = "/app/bench.py"

# ---------- hidden RHS family ----------
def make_rhs(kind, params):
    k = dict(params or {})
    if kind == "pendulum":
        g = float(k.get("g", 1.0)); c = float(k.get("c", 0.25))
        return lambda t, y: np.array([y[1], -g*np.sin(y[0]) - c*y[1]])
    if kind == "pendulum_batch":
        g = float(k.get("g", 1.0)); c = float(k.get("c", 0.25))
        return lambda t, Y: np.column_stack([Y[:, 1], -g*np.sin(Y[:, 0]) - c*Y[:, 1]])
    if kind == "vdp":
        mu = float(k.get("mu", 1.3))
        return lambda t, y: np.array([y[1], mu*(1.0 - y[0]**2)*y[1] - y[0]])
    if kind == "rotation":
        w = float(k.get("w", 7.0)); d = float(k.get("decay", 0.0))
        return lambda t, y: np.array([-w*y[1] - d*y[0], w*y[0] - d*y[1]])
    if kind == "stiff":
        kk = float(k.get("k", 600.0)); f = float(k.get("freq", 7.0))
        return lambda t, y: np.array([-kk*(y[0] - np.sin(f*t))])
    raise ValueError("unknown kind %s" % kind)

def mirror_batch(rhs, D):
    def rb(t, Y):
        return np.array([rhs(t, Y[i]) for i in range(Y.shape[0])])
    return rb

def reference(rhs, y0, ts):
    return solve_ivp(rhs, (ts[0], ts[-1]), np.asarray(y0, float).ravel(),
                     t_eval=ts, method="DOP853", rtol=1e-11, atol=1e-13)

def build_ts(c):
    mode = c["ts"].get("mode")
    if mode == "lin":
        return np.linspace(float(c["ts"]["start"]), float(c["ts"]["end"]), int(c["ts"]["n"]))
    if mode == "log":
        a = float(np.log(float(c["ts"]["start"]))); b = float(np.log(float(c["ts"]["end"])))
        return np.exp(np.linspace(a, b, int(c["ts"]["n"])))
    if mode == "points":
        return np.array([float(x) for x in c["ts"]["points"]])
    raise ValueError("unknown ts mode")

def close_v(a, b, rtol=1e-6):
    return abs(a - b) <= rtol * max(1.0, abs(a), abs(b))

# ---------- hidden scenarios ----------
hidden = sorted(glob.glob("/tests/hidden/*.json"))
if not hidden:
    fail("no hidden cases mounted")
    print("REWARD=%d" % reward)
    write_reward()
    sys.exit(0)

for hp in hidden:
    with open(hp) as f:
        case = json.load(f)
    bn = os.path.basename(hp)
    kind = case["kind"]
    atol = float(case["atol"])
    bf = float(case["budget_factor"])
    ts = build_ts(case)
    params = case.get("params") or {}

    if case.get("batched"):
        sp = case["states"]
        rng = np.random.default_rng(37 + len(ts))
        Y0 = rng.uniform(float(sp["lo"]), float(sp["hi"]), size=(int(sp["n"]), int(sp.get("dim", 2))))
        if sp.get("v0"):
            Y0[:, 1] *= float(sp["v0"])
        rhsb = make_rhs("pendulum_batch", params)
        nfmax = 1
        for y in Y0:
            sol = reference(make_rhs("pendulum", params), y, ts)
            if sol.success:
                nfmax = max(nfmax, sol.nfev)
        ceil = int(bf * nfmax)
        cnt = {"n": 0}
        def wit(t, Y):
            cnt["n"] += 1
            return rhsb(t, Y)
        YB = integ.integrate_many(wit, ts, Y0, budget=ceil, atol=atol)
        ok = True
        for j, y in enumerate(Y0):
            R = reference(make_rhs("pendulum", params), y, ts)
            if not R.success:
                fail("[%s] DOP853 ref failed row %d" % (bn, j)); ok = False; continue
            err = float(np.max(np.abs(YB[j] - R.y.T)))
            if err > atol:
                fail("[%s] batched row %d accerr %.3e > atol" % (bn, j, err)); ok = False
            if not np.all(np.isfinite(YB[j])):
                fail("[%s] batched row %d non-finite" % (bn, j)); ok = False
        if cnt["n"] > ceil:
            fail("[%s] batched eval calls %d > ceiling %d" % (bn, cnt["n"], ceil)); ok = False
        # serial vs batched speed + agreement
        t0 = time.perf_counter()
        ser = np.array([integ.integrate(make_rhs("pendulum", params), ts, y,
                                        budget=ceil, atol=atol)[-1] for y in Y0])
        t_ser = time.perf_counter() - t0
        t0 = time.perf_counter()
        BB = integ.integrate_many(wit, ts, Y0, budget=ceil, atol=atol)
        t_bat = time.perf_counter() - t0
        if t_ser <= 0 or t_bat <= 0:
            fail("[%s] degenerate timing" % bn); ok = False
        else:
            spd = t_ser / t_bat
            if spd < 2.0:
                fail("[%s] batched speedup %.2f < 2.0" % (bn, spd)); ok = False
            if np.max(np.abs(ser - BB[:, -1])) > atol:
                fail("[%s] serial/batched mismatch" % bn); ok = False
    else:
        sp = case["states"]
        rng = np.random.default_rng(3)
        y0 = rng.uniform(float(sp["lo"]), float(sp["hi"]), size=int(sp.get("dim", 2)))
        rhs = make_rhs(kind, params)
        R = reference(rhs, y0, ts)
        if not R.success:
            fail("[%s] DOP853 reference failed" % bn); continue
        ceil = int(bf * R.nfev)
        cnt = {"n": 0}
        def wit(t, y):
            cnt["n"] += 1
            return rhs(t, y)
        Y = integ.integrate(wit, ts, y0, budget=ceil, atol=atol)
        err = float(np.max(np.abs(Y - R.y.T)))
        if err > atol:
            fail("[%s] accerr %.3e > atol %s" % (bn, err, atol))
        if not np.all(np.isfinite(Y)):
            fail("[%s] non-finite output" % bn)
        if cnt["n"] > ceil:
            fail("[%s] eval calls %d > ceiling %d" % (bn, cnt["n"], ceil))
        # integrate_many on a single-row portfolio
        try:
            OB = integ.integrate_many(mirror_batch(rhs, len(y0)), ts, y0.reshape(1, -1),
                                      budget=ceil, atol=atol)
            if np.all(np.isfinite(OB[0])) and np.max(np.abs(OB[0] - R.y.T)) > atol:
                fail("[%s] integrate_many(1 row) inaccurate" % bn)
        except Exception as e:
            fail("[%s] integrate_many(1 row) raised: %s" % (bn, e))

# ---------- eig checks ----------
rng = np.random.default_rng(2468)
mats = {
    "asym_complex": np.array([
        [2.0, -3.0, 0.0],
        [3.0, 2.0, 0.0],
        [0.5, 0.1, -8.0]]),
    "mixed_scale": np.array([[1e-6, 0.0], [0.0, 5e3]]),
    "neg_dom": np.array([[-4.0, 1.0, 0.0],
                         [1.0, -2.0, 0.5],
                         [0.0, 0.5, -3.0]]),
    "rand7": rng.normal(size=(7, 7)),
}
for name, A0 in mats.items():
    A0 = np.asarray(A0, float)
    vals = np.linalg.eigvals(A0)
    refv = vals[int(np.argmax(np.abs(vals)))]
    got = eig.dominant(A0)
    if abs(abs(got) - abs(refv)) > 1e-6 * max(1.0, abs(refv)):
        fail("eig.dominant(%s) magnitude mismatch %.4g vs %.4g" % (name, abs(got), abs(refv)))
    if not close_v(got, refv, 1e-6):
        fail("eig.dominant(%s) %s != ref %s" % (name, got, refv))
    kk = min(A0.shape[0], 3)
    row = eig.spectrum_row(A0, kk)
    if len(row) != kk:
        fail("eig.spectrum_row(%s) len %d != %d" % (name, len(row), kk))
    else:
        for m in range(1, kk + 1):
            rv = np.linalg.eigvals(A0[:m, :m])
            rmv = rv[int(np.argmax(np.abs(rv)))]
            if not close_v(row[m - 1], rmv, 1e-6):
                fail("eig.spectrum_row(%s) m=%d %s != %s" % (name, m, row[m - 1], rmv))

# runtime bound n=400
BIG = rng.normal(size=(400, 400))
t0 = time.perf_counter(); eig.dominant(BIG); t_dom = time.perf_counter() - t0
t0 = time.perf_counter(); _ = np.linalg.eigvals(BIG); t_ref = time.perf_counter() - t0
if t_ref > 0 and t_dom > 15.0 * t_ref + 0.05:
    fail("eig.dominant runtime %.3f > 15x np %.3f" % (t_dom, t_ref))

# ---------- bench.py ----------
try:
    res = subprocess.run([sys.executable, BPATH], capture_output=True, text=True, timeout=180)
    if res.returncode != 0:
        fail("bench.py non-zero exit: %s" % res.stderr[-400:])
    else:
        kv = {}
        for ln in res.stdout.splitlines():
            if "=" in ln:
                a, b = ln.split("=", 1)
                kv[a.strip()] = b.strip()
        try:
            correct = float(kv["correct"]); speed = float(kv["speedup"])
            if correct < 0.9995:
                fail("bench.py correct %.5f too low" % correct)
            if speed <= 1.5:
                fail("bench.py speedup %.3f too low" % speed)
        except Exception:
            fail("bench.py report keys malformed: %s" % list(kv.keys()))
except Exception as e:
    fail("bench.py run failed: %s" % e)

print("REWARD=%d" % reward)
write_reward()
PY
echo "REWARD_FILE=$(cat /logs/verifier/reward.txt)"