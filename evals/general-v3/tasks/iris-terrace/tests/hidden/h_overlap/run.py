#!/usr/bin/env python3
"""Hidden spectral-case driver: runs /app/fit_spectra.py on data.csv and
checks every recovered peak parameter against the true values in params.json
within the tolerances in tol.json (independent ground truth)."""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
data = os.path.join(HERE, "data.csv")
truth = json.load(open(os.path.join(HERE, "params.json")))["peaks"]
tol = json.load(open(os.path.join(HERE, "tol.json")))
out = "/tmp/hidden_spectral_fit.json"

if os.path.exists(out):
    os.remove(out)
subprocess.run([sys.executable, "/app/fit_spectra.py", data, "--out", out],
               check=True, capture_output=True, text=True)
fits = json.load(open(out))["peaks"]

if len(fits) != len(truth):
    print("FAIL peak-count", len(fits), "vs", len(truth))
    sys.exit(1)

# greedy nearest-center assignment between fitted and true peaks (both asc)
used = [False] * len(truth)
for f in fits:
    cand = [j for j in range(len(truth)) if not used[j]]
    j = min(cand, key=lambda j: abs(f["center"] - truth[j]["center"]))
    used[j] = True
    t = truth[j]
    if abs(f["center"] - t["center"]) > tol["center"]:
        print("FAIL center", f["center"], "truth", t["center"]); sys.exit(1)
    if abs(f["width"] - t["width"]) > tol["width"] * max(t["width"], 1e-6):
        print("FAIL width", f["width"], "truth", t["width"]); sys.exit(1)
    if abs(f["amplitude"] - t["amplitude"]) > tol["amplitude"] * max(t["amplitude"], 1e-6):
        print("FAIL amplitude", f["amplitude"], "truth", t["amplitude"]); sys.exit(1)
    if abs(f["offset"] - t["offset"]) > tol["offset"]:
        print("FAIL offset", f["offset"], "truth", t["offset"]); sys.exit(1)

print("OK spectral peaks=%d" % len(fits))
