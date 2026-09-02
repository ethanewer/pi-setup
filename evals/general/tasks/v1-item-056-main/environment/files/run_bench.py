#!/usr/bin/env python3
"""Benchmark harness for item-56: compare the fast C extension to the reference,
then write the machine-readable report to /app/out/report.json."""
import json
import os
import time

import numpy as np

import native
from port_math import stats_reference

os.makedirs("/app/out", exist_ok=True)

mu = np.loadtxt("/app/mu.txt")
cov = np.loadtxt("/app/cov.txt")
w = np.loadtxt("/app/w.txt")
N = int(len(mu))

ref_ret, ref_var = stats_reference(w, mu, cov)

cov_flat = cov.flatten().tolist()
t0 = time.perf_counter()
fast = native.eval(mu.tolist(), cov_flat, w.tolist(), N)
fast_sec = time.perf_counter() - t0
fast_ret, fast_var = float(fast[0]), float(fast[1])

# timing the numpy reference (best possible python)
t0 = time.perf_counter()
for _ in range(200):
    stats_reference(w, mu, cov)
ref_sec = (time.perf_counter() - t0) / 200.0

match = (
    abs(fast_ret - ref_ret) / max(1.0, abs(ref_ret)) < 1e-6
    and abs(fast_var - ref_var) / max(1.0, abs(ref_var)) < 1e-6
)

report = {
    "ref_ret": ref_ret,
    "ref_var": ref_var,
    "fast_ret": fast_ret,
    "fast_var": fast_var,
    "match": bool(match),
    "ref_sec": ref_sec,
    "fast_sec": fast_sec,
    "speedup": ref_sec / max(fast_sec, 1e-9),
}
with open("/app/out/report.json", "w") as f:
    json.dump(report, f)
print(json.dumps(report, indent=2))