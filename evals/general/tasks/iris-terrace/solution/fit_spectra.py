#!/usr/bin/env python3
"""fit_spectra.py - crop each spectral peak's local window and fit a lorentzian.

Model:  y(x) = offset + amplitude * width**2 / ((x - center)**2 + width**2)

Usage:
    python3 fit_spectra.py INPUT.csv --out OUT.json [--n N] [--prominence P]

INPUT.csv is a two-column whitespace- (or comma-) separated file.  A single
header row of non-numeric tokens is ignored; blank lines are ignored.
Detected peaks (ascending center) dominate the output JSON:
    {"peaks":[{"center":..,"width":..,"amplitude":..,"offset":..}, ...]}
"""
import argparse
import json
import sys

import numpy as np
from scipy.optimize import curve_fit
from scipy.signal import find_peaks


def read_input(path):
    """Robust reader: skip blanks and any non-numeric header row."""
    xs, ys = [], []
    for line in open(path):
        line = line.strip()
        if not line:
            continue
        parts = line.replace(",", " ").split()
        if len(parts) < 2:
            continue
        try:
            xs.append(float(parts[0]))
            ys.append(float(parts[1]))
        except ValueError:
            continue
    if len(xs) < 8:
        raise ValueError("not enough data points in %s" % path)
    return np.asarray(xs, dtype=float), np.asarray(ys, dtype=float)


def lorentzian(x, center, width, amplitude, offset):
    return offset + amplitude * width * width / ((x - center) ** 2 + width * width)


def fit_spectrum(path, prominence=None, npeaks=None):
    x, y = read_input(path)
    if prominence is None:
        prominence = max(0.01, (float(np.max(y)) - float(np.min(y))) * 0.06)
    idx, _ = find_peaks(y, prominence=prominence)
    if npeaks is not None and len(idx) > npeaks:
        # keep the tallest requested number of peaks
        idx = idx[np.argsort(y[idx])[::-1]][:npeaks]
        idx = np.sort(idx)
    if len(idx) == 0:
        raise RuntimeError("no peaks detected with prominence %r" % prominence)

    results = []
    dx = float(np.median(np.diff(x))) if len(x) > 1 else 1.0
    for i, p in enumerate(idx):
        il = int(idx[i - 1]) if i > 0 else None
        ir = int(idx[i + 1]) if i + 1 < len(idx) else None
        lo = (p + il) // 2 if il is not None else 0
        hi = (p + (ir if ir is not None else len(x))) // 2 + (0 if ir is not None else 1)
        lo = max(0, int(lo)); hi = min(int(hi), len(x))
        if hi - lo < 6:
            lo = max(0, p - 40); hi = min(len(x), p + 41)
        xs = x[lo:hi]; ys = y[lo:hi]
        span = float(xs.max() - xs.min())
        c0 = float(x[p]); ypk = float(y[p])
        b0 = float(np.median(np.concatenate([ys[:3], ys[-3:]])) if len(ys) >= 6 else np.mean(ys))
        a0 = max(ypk - b0, 1e-6)
        w0 = max(dx * 4.0, span * 0.04)
        p0 = [c0, w0, a0, b0]
        lo_b = [c0 - span, 1e-4, a0 * 0.05, float(ys.min()) - 0.5]
        hi_b = [c0 + span, span * 1.5, a0 * 6.0 + 1.0, float(ys.max()) + 0.5]
        try:
            pop, _ = curve_fit(lorentzian, xs, ys, p0=p0, bounds=(lo_b, hi_b), maxfev=20000)
            c, w, a, b = pop
        except Exception:
            c, w, a, b = p0
        results.append((float(c), float(w), float(a), float(b)))

    results.sort(key=lambda t: t[0])
    return {"peaks": [{"center": c, "width": w, "amplitude": a, "offset": b}
                      for c, w, a, b in results]}


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("input")
    ap.add_argument("--out", required=True)
    ap.add_argument("--n", type=int, default=None)
    ap.add_argument("--prominence", type=float, default=None)
    args = ap.parse_args(argv)
    res = fit_spectrum(args.input, prominence=args.prominence, npeaks=args.n)
    with open(args.out, "w") as f:
        json.dump(res, f, indent=2)
    print(json.dumps(res))
    return 0


if __name__ == "__main__":
    sys.exit(main())
