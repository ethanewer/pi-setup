#!/usr/bin/env python3
"""cedar-jetty verifier. Mounted at /tests at grading time (read-only).

Checks every deliverable in /app and re-runs each kernel on the hidden inputs in
/tests/hidden against an independent reference computation. Exits 0 on full pass,
nonzero on any failure.
"""
import math
import os
import sys

import numpy as np

APP = "/app"
sys.path.insert(0, APP)
HIDDEN = "/tests/hidden"

failures = []


def _emit(code):
    if not os.path.isdir("/logs/verifier"):
        os.makedirs("/logs/verifier", exist_ok=True)
    reward = 1 if (code == 0 and not failures) else 0
    with open("/logs/verifier/reward.txt", "w", encoding="utf-8") as fh:
        fh.write(str(reward) + "\n")
    print(f"REWARD={reward}")


def check(name, cond, detail=""):
    if not cond:
        failures.append(f"{name}: {detail}")
        print(f"  [FAIL] {name} {detail}")
    else:
        print(f"  [ok]   {name}")


# ---------------------------------------------------------------------------
# 0. Load the subject module.
# ---------------------------------------------------------------------------
try:
    import kernels
except Exception as exc:  # noqa: BLE001
    check("import kernels", False, repr(exc))
    _emit(1)
    sys.exit(1)


# ---------------------------------------------------------------------------
# 1. Denylist scan on the ODE solver.
# ---------------------------------------------------------------------------
src = open("/app/kernels.py", encoding="utf-8", errors="replace").read()
forbidden = ["scipy.integrate", "solve_ivp", "odeint", "scipy.optimize"]
bad = [t for t in forbidden if t in src]
check("denylist: no forbidden numeric-integration imports", not bad, f"found {bad}")


# ---------------------------------------------------------------------------
# 2. Visible deliverable /app/out.npy.
# ---------------------------------------------------------------------------
try:
    out = np.load(f"{APP}/out.npy")
except Exception as exc:  # noqa: BLE001
    check("out.npy present", False, repr(exc))
else:
    check("out.npy is 2-D float real", out.ndim == 2 and out.dtype.kind == "f" and np.iscomplexobj(out) is False)
    check("out.npy non-negative finite", out.size > 0 and np.all(np.isfinite(out)) and np.all(out >= -1e-15))
    # rebuild visible reference
    fs = 2048.0
    L = 2048
    t = np.arange(L) / fs
    signal = 3.0 * np.sin(2 * np.pi * 220.0 * t) + 1.5 * np.sin(2 * np.pi * 880.0 * t)
    ref = kernels.stft_mag(signal, fs=2048.0, nperseg=256, noverlap=192, nfft=512)
    check("out.npy shape matches visible ref", out.shape == ref.shape,
          f"{out.shape} vs {ref.shape}")
    check("out.npy equals visible stft_mag reference",
          np.allclose(out, ref, rtol=1e-9, atol=1e-12))
    check("out.npy is linear magnitude (not dB)", float(out.max()) > 1.0)


# ---------------------------------------------------------------------------
# Helpers for independent reference computation.
# ---------------------------------------------------------------------------
def ref_kl(a, b):
    a = np.asarray(a, dtype=float); b = np.asarray(b, dtype=float)
    a = a / a.sum(); b = b / b.sum()
    pos = a > 0.0
    return float(np.sum(a[pos] * np.log(a[pos] / b[pos])))


def ref_num(v):
    if isinstance(v, str):
        if v == "ERR":
            return None
        try:
            return float(v)
        except (TypeError, ValueError):
            return None
    if isinstance(v, bool):
        return float(v)
    if isinstance(v, (int, float)):
        return float(v)
    return None


def ref_half_up(x, digits):
    factor = 10.0 ** digits
    v = math.floor(float(x) * factor + 0.5) / factor
    return max(0.0, min(1.0, v))


def ref_round_accuracy(model, truth):
    out = {}
    for r in set(model) | set(truth):
        m = model.get(r, {}) if isinstance(model.get(r), dict) else {}
        t = truth.get(r, {}) if isinstance(truth.get(r), dict) else {}
        correct = total = 0
        for qid in set(m) | set(t):
            if qid not in m or qid not in t:
                continue
            a = ref_num(m[qid]); b = ref_num(t[qid])
            if a is None or b is None:
                continue
            total += 1
            if abs(a - b) < 5e-3:
                correct += 1
        acc = ref_half_up(correct / total, 3) if total else None
        out[r] = {"correct": correct, "total": total, "accuracy": acc}
    return out


# ---------------------------------------------------------------------------
# 3. Hidden cases.
# ---------------------------------------------------------------------------
import json  # noqa: E402
import glob  # noqa: E402

hidden = sorted(glob.glob(f"{HIDDEN}/*.json"))
if not hidden:
    check("hidden cases present", False, f"no json in {HIDDEN}")


for hf in hidden:
    data = json.load(open(hf, encoding="utf-8"))
    kind = data.get("kind")
    base = os.path.basename(hf)
    if kind == "ode":
        try:
            got = kernels.hand_kin(data["c"], data["y0"], data["t_beg"], data["t_end"], data["step"])
        except Exception as exc:  # noqa: BLE001
            check(f"{base}: hand_kin runs", False, repr(exc)); continue
        ref = data["y0"] * math.exp(-data["c"] * (data["t_end"] - data["t_beg"]))
        ok = math.isfinite(got) and math.isclose(got, ref, rel_tol=1e-4, abs_tol=1e-12)
        check(f"{base}: hand_kin matches analytic solution", ok, f"got {got!r} ref {ref!r}")
    elif kind == "kl":
        p = np.asarray(data["p"], dtype=float)
        rf, rb = data["r_forward"], data["r_backward"]
        try:
            q = kernels.smoothed_distribution(p, rf, rb)
        except Exception as exc:  # noqa: BLE001
            check(f"{base}: smoothed_distribution runs", False, repr(exc)); continue
        q = np.asarray(q, dtype=float)
        check(f"{base}: q length == p length", q.shape == p.shape, f"{q.shape} vs {p.shape}")
        check(f"{base}: q strictly positive", bool(q.size) and bool(np.all(q > 0)))
        check(f"{base}: q sums to 1", bool(q.size) and abs(float(q.sum()) - 1.0) <= 1e-9, str(q.sum()))
        check(f"{base}: q finite", bool(np.all(np.isfinite(q))))
        if q.size:
            df = ref_kl(q, p); dbb = ref_kl(p, q)
            check(f"{base}: forward KL <= r_forward", df <= rf + 1e-6, f"KL(q||p)={df:.6g} r={rf}")
            check(f"{base}: reverse KL <= r_backward", dbb <= rb + 1e-6, f"KL(p||q)={dbb:.6g} r={rb}")
    elif kind == "stft":
        sig = np.asarray(data["signal"], dtype=float)
        try:
            got = kernels.stft_mag(sig, data["fs"], data["nperseg"], data["noverlap"], data["nfft"])
        except Exception as exc:  # noqa: BLE001
            check(f"{base}: stft_mag runs", False, repr(exc)); continue
        got = np.asarray(got, dtype=float)
        from scipy.signal import stft as _stft
        _, _, z = _stft(sig, fs=data["fs"], window="hann", nperseg=data["nperseg"],
                        noverlap=data["noverlap"], nfft=data["nfft"],
                        detrend=False, return_onesided=True, boundary="zeros", padded=True)
        ref = np.abs(z)
        check(f"{base}: stft shape matches", got.shape == ref.shape, f"{got.shape} vs {ref.shape}")
        check(f"{base}: stft matches identical scipy call",
              np.allclose(got, ref, rtol=1e-9, atol=1e-12))
    elif kind == "round":
        try:
            got = kernels.round_accuracy(data["model"], data["truth"])
        except Exception as exc:  # noqa: BLE001
            check(f"{base}: round_accuracy runs", False, repr(exc)); continue
        gref = ref_round_accuracy(data["model"], data["truth"])
        gmap = {str(r.get("round")): r for r in got}
        allok = set(gmap.keys()) == set(gref.keys())
        for r, rref in gref.items():
            rg = gmap.get(str(r))
            if rg is None:
                allok = False; continue
            if (rg["correct"] != rref["correct"] or rg["total"] != rref["total"]
                    or rg["accuracy"] != rref["accuracy"]):
                allok = False
        check(f"{base}: round_accuracy matches reference", allok,
              f"got {got} ref-mapped {gref}")
    elif kind == "sym":
        try:
            res = kernels.symbolic_integral(data["degree"])
        except Exception as exc:  # noqa: BLE001
            check(f"{base}: symbolic_integral runs", False, repr(exc)); continue
        import sympy as sp
        ok = True
        if not isinstance(res.get("variable"), sp.Basic):
            ok = False
        integrand = res.get("integrand"); lo = res.get("lower"); hi = res.get("upper")
        try:
            val = sp.integrate(integrand, (res.get("variable"), lo, hi))
            exact = sp.Rational(1, data["degree"] + 1)
            ok = ok and (val == exact) and isinstance(lo, sp.Integer) and isinstance(hi, sp.Integer)
        except Exception as exc:  # noqa: BLE001
            ok = False
            val = f"<error {exc}>"
        check(f"{base}: symbolic integral is exact Rational(1,{data['degree']+1})", ok,
              f"got {val!r} (variable={res.get('variable')!r}, lo={lo!r}, hi={hi!r})")


_emit(0 if not failures else 1)
sys.exit(0 if not failures else 1)
