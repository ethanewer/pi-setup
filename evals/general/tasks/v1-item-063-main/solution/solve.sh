#!/bin/bash
set -euo pipefail

mkdir -p /app/out

python3 - <<'PY'
import json
import numpy as np
from scipy.optimize import curve_fit

x, y = np.genfromtxt('/app/data/spec.csv', delimiter=',', skip_header=1, unpack=True)

def model(xv, b, a1, c1, w1, a2, c2, w2, a3, c3, w3):
    ys = np.full_like(xv, b, float)
    for (a, cc, ww) in [(a1, c1, w1), (a2, c2, w2), (a3, c3, w3)]:
        ys += a * (ww * ww / ((xv - cc) ** 2 + ww * ww))
    return ys

init = json.load(open('/app/data/init_guess.json'))
pks = init['peaks']
p0 = [init['baseline']] + [v for p in pks for v in (p['amplitude'], p['center'], p['width'])]

# a) bumpst most prototypical attempt first
popt = p0
rms = float('inf')
for scale_amp in (1.0, 3.0, 0.3):
    p = [p0[0]] + [p0[i] * (scale_amp if i % 3 == 1 else 1.0) for i in range(1, len(p0))]
    try:
        pr, _ = curve_fit(model, x, y, p0=p, maxfev=200000)
        r = model(x, *pr)
        rr = float(np.sqrt(np.mean((r - y) ** 2)))
        if rr < rms:
            popt, rms = pr, rr
    except Exception:
        continue

yr = model(x, *popt)
rms = float(np.sqrt(np.mean((yr - y) ** 2)))
peaks = [
    {"amplitude": float(popt[i]), "center": float(popt[i + 1]), "width": float(popt[i + 2])}
    for i in (1, 4, 7)
]
out = {"baseline": float(popt[0]), "peaks": peaks, "rms": rms}
with open('/app/out/fit.json', 'w') as f:
    json.dump(out, f, indent=2)
print("rms =", rms)
PY