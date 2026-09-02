#!/usr/bin/env python3
"""fit_spectra.py -- crop each spectral peak's local window and fit a
lorentzian profile (center / width / amplitude / offset).

Usage:
    python3 fit_spectra.py <input.csv> -o <out.json>

Input CSV has a header `wavelength,intensity`. One or more peaks are detected;
each is cropped to its local valve-to-valve window and fitted with

    y(x) = offset + amplitude * width^2 / ((x - center)^2 + width^2)

Output JSON: {"peaks": [ {center,width,amplitude,offset}, ... ]}

Edge behaviour:
  * a spectrum with no detectable peaks yields {"peaks": []}
  * a constant/shallow spectrum yields {"peaks": []}
  * empty or header-only input yields {"peaks": []}
"""
import argparse
import csv
import json

import numpy as np
from scipy.optimize import curve_fit


def lorentzian(x, center, width, amplitude, off):
    return off + amplitude * (width * width) / ((x - center) ** 2 + width * width)


def _read(path):
    xs = []
    ys = []
    with open(path, newline="") as fh:
        reader = csv.reader(fh)
        next(reader, None)  # header
        for row in reader:
            if not row or len(row) < 2:
                continue
            xs.append(float(row[0]))
            ys.append(float(row[1]))
    return np.asarray(xs, float), np.asarray(ys, float)


def _is_valley(y, i):
    n = len(y)
    if i <= 0 or i >= n - 1:
        return True
    return y[i] <= y[i - 1] and y[i] <= y[i + 1]


def _base_value(y, i):
    """Value of the trough just left and just right of index i."""
    n = len(y)
    left = 0
    while left < i and not _is_valley(y, left):
        left += 1
    right = n - 1
    while right > i and not _is_valley(y, right):
        right -= 1
    return min(float(y[left]), float(y[right]))


def detect_peaks(y):
    """Strict local maxima with meaningful local prominence."""
    n = len(y)
    if n < 3:
        return []
    rng = float(y.max()) - float(y.min())
    if rng <= 0:
        return []
    thr = 0.05 * rng
    peaks = []
    for i in range(1, n - 1):
        if y[i] > y[i - 1] and y[i] > y[i + 1]:
            if float(y[i]) - _base_value(y, i) >= thr:
                peaks.append(i)
    return peaks


def fit_one(x, y, p):
    n = len(x)
    left = p
    while left > 0 and not _is_valley(y, left - 1):
        left -= 1
    right = p
    while right < n - 1 and not _is_valley(y, right + 1):
        right += 1
    xw = x[left:right + 1]
    yw = y[left:right + 1]
    if len(xw) < 6:
        return None
    off0 = float(min(yw[0], yw[-1]))
    c0 = float(x[p])
    a0 = float(y[p] - off0)
    if a0 <= 0:
        return None
    w0 = 1.0
    half = off0 + a0 / 2.0
    for direction in (1, -1):
        j = p
        while 0 <= j < n and y[j] >= half:
            j += direction
        if 0 <= j < n:
            w0 = max(w0, abs(float(x[j]) - c0))
    try:
        popt, _ = curve_fit(
            lorentzian, xw, yw, p0=[c0, w0, a0, off0],
            bounds=(
                [c0 - 4.0, 1e-9, 1e-9, yw.min() - 2.0],
                [c0 + 4.0, 1e6, 1e9, yw.max() + 2.0],
            ),
            maxfev=30000,
        )
        c, w, a, off = popt
        return {
            "center": float(c),
            "width": float(w),
            "amplitude": float(a),
            "offset": float(off),
        }
    except Exception:  # noqa: BLE001
        return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("input")
    ap.add_argument("-o", "--output", required=True)
    args = ap.parse_args()
    x, y = _read(args.input)
    peaks = []
    if len(x) >= 3:
        for p in detect_peaks(y):
            hit = fit_one(x, y, p)
            if hit is not None:
                peaks.append(hit)
    peaks.sort(key=lambda d: d["center"])
    with open(args.output, "w") as f:
        json.dump({"peaks": peaks}, f)


if __name__ == "__main__":
    main()