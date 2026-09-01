#!/usr/bin/env bash
# cedar-jetty oracle: author the kernels module and run the visible analysis.
set -euo pipefail

# ----------------------------------------------------------------------
# 1. Write the kernels module to /app/kernels.py (the real deliverable).
# ----------------------------------------------------------------------
cat > /app/kernels.py <<'PYEOF'
"""cedar-jetty signal & calibration kernels.

Pure numeric kernels for the Cedar Jetty survey-buoy pipeline. The ODE
integration in :func:`hand_kin` is hand-written Runge-Kutta and deliberately
avoids every mainstream numeric-integration / optimization stack.
"""
import math

import numpy as np


def hand_kin(c, y0, t_beg, t_end, step):
    """Forward-integrate dy/dt = -c*y from (t_beg, y0) to t_end with a hand
    written classical 4th-order Runge-Kutta scheme. Returns the final y (float).
    """
    if step <= 0.0:
        raise ValueError("hand_kin: step must be positive")
    if c < 0.0:
        raise ValueError("hand_kin: c must be >= 0")
    if t_end < t_beg:
        raise ValueError("hand_kin: t_end must be >= t_beg")
    n = max(1, int(math.ceil((t_end - t_beg) / step)))
    h = (t_end - t_beg) / float(n)
    y = float(y0)
    for _ in range(n):
        k1 = -c * y
        k2 = -c * (y + 0.5 * h * k1)
        k3 = -c * (y + 0.5 * h * k2)
        k4 = -c * (y + h * k3)
        y = y + (h / 6.0) * (k1 + 2.0 * k2 + 2.0 * k3 + k4)
    return float(y)


def _kl(a, b):
    a = np.asarray(a, dtype=float)
    b = np.asarray(b, dtype=float)
    a = a / a.sum()
    b = b / b.sum()
    pos = a > 0.0
    return float(np.sum(a[pos] * np.log(a[pos] / b[pos])))


def smoothed_distribution(p, r_forward, r_backward):
    """Return a strictly-positive, unit-sum distribution q of the same length as
    strictly-positive p with KL(q||p) <= r_forward and KL(p||q) <= r_backward,
    by shrinking an additive-uniform smooth until both radii are met.
    """
    p = np.asarray(p, dtype=float)
    p = p / p.sum()
    if np.any(p <= 0.0):
        raise ValueError("smoothed_distribution: p must be strictly positive")
    if min(r_forward, r_backward) <= 0.0:
        q = p.copy()  # a zero radius forces q == p exactly (both KLs = 0)
    else:
        u = np.full_like(p, 1.0 / p.size)
        alpha = 0.5
        q = None
        for _ in range(120):
            cand = (1.0 - alpha) * p + alpha * u
            cand = cand / cand.sum()
            if _kl(cand, p) <= r_forward and _kl(p, cand) <= r_backward:
                q = cand
                break
            alpha = alpha / 2.0
        if q is None:
            q = p.copy()
    q = np.maximum(q, np.finfo(float).tiny)
    return q / q.sum()


def stft_mag(signal, fs, nperseg, noverlap, nfft):
    """scipy STFT magnitude spectrogram with the fixed documented settings."""
    from scipy.signal import stft as _stft

    signal = np.asarray(signal, dtype=float)
    _, _, z = _stft(
        signal, fs=fs, window="hann", nperseg=nperseg, noverlap=noverlap,
        nfft=nfft, detrend=False, return_onesided=True,
        boundary="zeros", padded=True,
    )
    return np.abs(z)


def _num(v):
    if isinstance(v, bool):
        return float(v)
    if isinstance(v, (int, float)):
        return float(v)
    if isinstance(v, str):
        if v == "ERR":
            return None
        try:
            return float(v)
        except (TypeError, ValueError):
            return None
    return None


def _half_up(x, digits):
    factor = 10.0 ** digits
    v = math.floor(float(x) * factor + 0.5) / factor
    return max(0.0, min(1.0, v))


def round_accuracy(model, truth, tol=5e-3):
    """Per-round accuracy dropping invalid (ERR) and unmatched question ids."""
    results = []
    for r in sorted(set(model) | set(truth), key=lambda k: (str(type(k)), str(k))):
        m = model.get(r, {}) if isinstance(model.get(r), dict) else {}
        t = truth.get(r, {}) if isinstance(truth.get(r), dict) else {}
        qids = sorted(set(m) | set(t), key=lambda k: (str(type(k)), str(k)))
        correct = 0
        total = 0
        for qid in qids:
            if qid not in m or qid not in t:
                continue
            a = _num(m[qid])
            b = _num(t[qid])
            if a is None or b is None:
                continue
            total += 1
            if abs(a - b) < tol:
                correct += 1
        acc = _half_up(correct / total, 3) if total else None
        results.append({"round": r, "correct": correct, "total": total, "accuracy": acc})
    return results


def symbolic_integral(degree):
    """Return (variable, integrand, lower, upper) sympy objects; exact integral of
    x**degree over [0,1] is Rational(1, degree+1)."""
    import sympy as sp
    degree = int(degree)
    if not (0 <= degree <= 12):
        raise ValueError("symbolic_integral: degree out of range 0..12")
    x = sp.Symbol("x")
    return {
        "variable": x,
        "integrand": x ** degree,
        "lower": sp.Integer(0),
        "upper": sp.Integer(1),
    }
PYEOF

# ----------------------------------------------------------------------
# 2. Run the visible analysis to produce /app/out.npy (RUN the work).
# ----------------------------------------------------------------------
cd /app
python3 - <<'PYEOF'
import numpy as np
import kernels

fs = 2048.0
L = 2048
t = np.arange(L) / fs
signal = 3.0 * np.sin(2 * np.pi * 220.0 * t) + 1.5 * np.sin(2 * np.pi * 880.0 * t)
out = kernels.stft_mag(signal, fs=2048.0, nperseg=256, noverlap=192, nfft=512)
np.save("/app/out.npy", out)
print("out.npy shape:", out.shape, "dtype:", out.dtype, "max:", out.max())
PYEOF

echo "cedar-jetty oracle complete"
ls -l /app/kernels.py /app/out.npy