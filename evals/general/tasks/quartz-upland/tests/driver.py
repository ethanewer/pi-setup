#!/usr/bin/env python3
"""Quartz Upland verifier driver.

Executes every deliverable (solve.py, reporting_converted.py, answer.json),
runs the solve module on hidden cases from /tests/hidden, checks dtypes/
tolerances/edge handling, and exits non-zero if any check fails.
"""
import glob
import importlib.util
import json
import math
import os
import subprocess
import sys

import numpy as np

failures = []


def chk(name, cond, detail=""):
    if cond:
        print("PASS ", name)
    else:
        failures.append(name)
        print("FAIL ", name, detail)


# ------------------------------ 0. deliverables present -------------------
for f in ("/app/solve.py", "/app/reporting_converted.py"):
    chk("present " + f, os.path.exists(f))

# ------------------------------ 1. run the built deliverables -------------
r = subprocess.run(["python3", "/app/solve.py"], cwd="/app", capture_output=True)
chk("solve.py default run", r.returncode == 0)
r2 = subprocess.run(["python3", "/app/reporting_converted.py"], cwd="/app",
                    capture_output=True)
chk("reporting_converted.py run", r2.returncode == 0)

# ------------------------------ 2. forbidden solver imports ---------------
src = open("/app/solve.py", encoding="utf-8").read()
for bad in ("import scipy", "from scipy"):
    chk("solve.py no " + bad, bad not in src)

# ------------------------------ 3. load module ----------------------------
spec = importlib.util.spec_from_file_location("solve", "/app/solve.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

# ------------------------------ 4. answer.json / visible fixture ----------
chk("answer.json present", os.path.exists("/app/answer.json"))
ans = json.load(open("/app/answer.json", encoding="utf-8"))
data = json.load(open("/app/input_data.json", encoding="utf-8"))
w = np.asarray(data["risk_weights"], dtype=np.float64)
S = np.asarray(data["risk_cov"], dtype=np.float64)
refris = float((w @ S @ w) / (w @ w))
chk("answer risk rtol",
    abs(ans["risk_score"] - refris) <= 1e-9 * abs(refris) + 1e-12,
    f"ans={ans['risk_score']} ref={refris}")
P = np.sort(np.asarray(data["dist_p"], dtype=np.float64))
Q = np.sort(np.asarray(data["dist_q"], dtype=np.float64))
refw = float(np.mean(np.abs(P - Q)))
chk("answer wasserstein", abs(ans["wasserstein"] - refw) <= 1e-12)
chk("answer attn dtype",
    str(ans["attention_dtype"]) in ("float16", "float32", "float64", "mixed"))
chk("answer attn finite", np.isfinite(float(ans["attention_sum"])))
chk("answer sample ok",
    bool(ans.get("sample_within")) and int(ans.get("sample_count", 0)) > 0
    and np.isfinite(ans.get("sample_mean")))

# ------------------------------ 5. reporting port greps -------------------
conv_src = open("/app/reporting_converted.py", encoding="utf-8").read()
for needle in ("pathlib", "configparser", "utf-8", "read_csv", "to_csv",
               "pandas"):
    chk("reporting uses " + needle, needle in conv_src)
for forbidden in ("import ConfigParser", "xrange(", ".iterkeys()",
                  "print \""):
    chk("reporting lacks legacy " + forbidden, forbidden not in conv_src)
if os.path.exists("/app/annual_summary.csv"):
    import pandas as pd
    outdf = pd.read_csv("/app/annual_summary.csv", encoding="utf-8")
    obs = pd.read_csv("/app/obs_daily.csv", encoding="utf-8")
    cfg = data  # start_year fixed by fixture
    sy = 1996
    filtered = obs[obs["year"] >= sy]
    expected = filtered.groupby("year")["maxtemp"].mean()
    ok_rows = True
    for yr, exp_v in expected.items():
        got = outdf.loc[outdf["year"] == yr, "mean_maxtemp"]
        if len(got) != 1 or abs(float(got.iloc[0]) - float(exp_v)) > 1e-9 * max(
                1.0, abs(float(exp_v))):
            ok_rows = False
    chk("annual_summary numbers", ok_rows and len(outdf) == len(expected))
else:
    chk("annual_summary.csv present", False)

# ------------------------------ 6. hidden cases -----------------------------
hdir = "/tests/hidden"
files = sorted(glob.glob(hdir + "/*.json"))
chk("hidden cases present", len(files) >= 2)

for fp in files:
    c = json.load(open(fp, encoding="utf-8"))
    probe = c["probe"]
    base = os.path.basename(fp)

    if probe == "risk":
        for i, ex in enumerate(c["cases"]):
            lbl = f"{base} risk#{i}"
            w = np.asarray(ex["w"], dtype=np.float64)
            S = np.asarray(ex["S"], dtype=np.float64)
            if ex["expect"] == "error":
                try:
                    m.risk_score(w, S)
                    chk(lbl + " raises", False)
                except Exception:
                    chk(lbl + " raises", True)
            else:
                ref = float((w @ S @ w) / (w @ w))
                try:
                    v = m.risk_score(w, S)
                    chk(lbl, abs(v - ref) <= 1e-9 * abs(ref) + 1e-12,
                        f"v={v} ref={ref}")
                except Exception as e:
                    chk(lbl, False, str(e))

    elif probe == "dist":
        for i, ex in enumerate(c["cases"]):
            lbl = f"{base} dist#{i}"
            p, q = ex["p"], ex["q"]
            if ex["expect"] == "error":
                try:
                    m.wasserstein(p, q)
                    chk(lbl + " raises", False)
                except Exception:
                    chk(lbl + " raises", True)
            else:
                if len(p) == 0 and len(q) == 0:
                    ref = 0.0
                else:
                    ref = float(np.mean(np.abs(
                        np.sort(np.asarray(p, float)) -
                        np.sort(np.asarray(q, float)))))
                try:
                    v = m.wasserstein(p, q)
                    chk(lbl, abs(v - ref) <= 1e-12, f"v={v} ref={ref}")
                    if len(p) > 0 and len(q) > 0:
                        try:
                            sym = abs(m.wasserstein(q, p) - v) <= 1e-12
                        except Exception:
                            sym = False
                        chk(lbl + " sym", sym)
                except Exception as e:
                    chk(lbl, False, str(e))

    elif probe == "attn":
        TOL = {"float16": 2e-3, "float32": 1e-5, "float64": 1e-12,
               "mixed": 1e-5}
        GTOL = {"float16": 5e-2, "float32": 1e-4, "float64": 1e-10,
                "mixed": 1e-4}
        OUTDT = {"float16": "float16", "float32": "float32",
                 "float64": "float64", "mixed": "float32"}
        for i, ex in enumerate(c["cases"]):
            lbl = f"{base} attn#{i}"
            dtype = ex["dtype"]
            try:
                out, grad = m.softmax_attention(ex["z"], dtype)
                ok = isinstance(out, np.ndarray)
                msg = ""
                if ok and str(out.dtype) != OUTDT[dtype]:
                    ok = False; msg = f"dtype {out.dtype} != {OUTDT[dtype]}"
                if ok and not np.all(np.isfinite(out)):
                    ok = False; msg = "out not finite"
                if ok and abs(float(out.sum()) - 1.0) > TOL[dtype]:
                    ok = False; msg = f"sum {out.sum():.5g} tol {TOL[dtype]}"
                if ok and not np.all(np.isfinite(grad)):
                    ok = False; msg = "grad not finite"
                if ok and dtype == "mixed":
                    # prove fp16 input is really consumed: two distinct fp16-
                    # collapsible scores must yield *identical* weights.
                    zarr = np.asarray(ex["z"], dtype=np.float64)
                    zq = zarr.astype(np.float16).astype(np.float32)
                    for a in range(zq.size):
                        for b in range(a + 1, zq.size):
                            if float(zq[a]) == float(zq[b]):
                                if float(out[a]) != float(out[b]):
                                    ok = False
                                    msg = "mixed did not consume fp16 input"
                                break
                        if not ok:
                            break
                if ok:
                    rs = float(np.abs(grad.sum(axis=1)).max())
                    if rs > GTOL[dtype]:
                        ok = False; msg = f"grad rowsum {rs:.5g}"
                chk(lbl, ok, msg)
            except Exception as e:
                chk(lbl, False, str(e))

    elif probe == "sample":
        TOLC = 1e-7

        def make_logp(ex):
            if ex.get("density") == "bimodal":
                def lp(x):
                    x = float(x)
                    return math.log(
                        math.exp(-0.5 * ((x - 4.0) / 0.5) ** 2) +
                        math.exp(-0.5 * ((x + 4.0) / 0.5) ** 2))
                return lp
            mu = ex.get("mu", 0.0)
            sig = ex.get("sig", 1.0)
            return lambda x: -0.5 * ((float(x) - mu) / sig) ** 2

        for i, ex in enumerate(c["cases"]):
            lbl = f"{base} sample#{i}"
            if ex["kind"] == "noncallable":
                try:
                    m.sample_density(10, ex["count"], ex["bounds"])
                    chk(lbl + " raises", False)
                except Exception:
                    chk(lbl + " raises", True)
                continue
            logp = make_logp(ex)
            lo, hi = ex["bounds"]
            if ex["expect"] == "error":
                try:
                    m.sample_density(logp, ex["count"], ex["bounds"])
                    chk(lbl + " raises", False)
                except m.NonLogConvexError:
                    chk(lbl + " raises NonLogConvex", True)
                except Exception:
                    chk(lbl + " raises", True)
            else:
                try:
                    out = m.sample_density(logp, ex["count"], ex["bounds"])
                    ok = (isinstance(out, np.ndarray)
                          and out.size == ex["count"]
                          and np.all(np.isfinite(out))
                          and float(out.min()) >= lo - 1e-9
                          and float(out.max()) <= hi + 1e-9)
                    chk(lbl, bool(ok),
                        f"size={getattr(out,'size',None)} n={ex['count']}")
                except Exception as e:
                    chk(lbl, False, str(e))

print("---")
if failures:
    print("FAILED checks:", failures)
    sys.exit(1)
print("all checks passed")
sys.exit(0)