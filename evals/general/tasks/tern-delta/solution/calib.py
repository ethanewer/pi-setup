#!/usr/bin/env python3
"""tern-delta oracle: the /app/calib.py deliverable + visible calibration."""
import json
import sys

import numpy as np


def _kl(a, b):
    a = np.asarray(a, dtype=float)
    b = np.asarray(b, dtype=float)
    mask = a > 0
    return float(np.sum(a[mask] * np.log(a[mask] / b[mask])))


def calibrate(p, r_forward, r_backward):
    p = np.asarray(p, dtype=float)
    if p.ndim != 1 or p.size == 0 or not np.all(np.isfinite(p)) \
            or np.any(p <= 0):
        raise ValueError("p must be a non-empty 1-D array of positive numbers")
    p = p / p.sum()
    if r_forward == 0 or r_backward == 0:
        return p.copy()
    u = np.full_like(p, 1.0 / p.size)
    alpha = 0.5
    for _ in range(200):
        q = (1.0 - alpha) * p + alpha * u
        if _kl(q, p) <= r_forward and _kl(p, q) <= r_backward:
            return q
        alpha /= 2.0
    return p.copy()


def main():
    prior = json.load(open("/app/prior.json"))
    q = calibrate(prior, 0.04, 0.06)
    with open("/app/calibrated.json", "w") as fh:
        json.dump([float(x) for x in q], fh)
    print("calibrated:", [round(float(x), 6) for x in q])


if __name__ == "__main__":
    main()
