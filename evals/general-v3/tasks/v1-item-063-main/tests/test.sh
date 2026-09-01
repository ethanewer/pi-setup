#!/bin/bash

mkdir -p /logs/verifier

reward=0

if [ -f /app/out/fit.json ]; then
python3 - <<'PY'
import json, sys
import numpy as np

x, y = np.genfromtxt('/app/data/spec.csv', delimiter=',', skip_header=1, unpack=True)

def model(x, b, peaks):
    ys = np.full_like(x, b, float)
    for p in peaks:
        a, c, w = p
        ys += a * (w * w / ((x - c) ** 2 + w * w))
    return ys

try:
    d = json.load(open('/app/out/fit.json'))
    b = float(d['baseline'])
    peaks = [(float(p['amplitude']), float(p['center']), float(p['width'])) for p in d['peaks']]
    rpt = float(d['rms'])
except Exception:
    sys.exit(1)

if len(peaks) != 3:
    sys.exit(1)
if any(not (300.0 <= p[1] <= 1600.0) or p[2] <= 0.0 for p in peaks):
    sys.exit(1)

yfit = model(x, b, peaks)
resid = float(np.sqrt(np.mean((yfit - y) ** 2)))
if resid > 0.5:
    sys.exit(1)
if abs(rpt - resid) > max(0.05, 0.1 * resid):
    sys.exit(1)

sys.exit(0)
PY
  if [ $? -eq 0 ]; then reward=1; else reward=0; fi
fi

echo "$reward" > /logs/verifier/reward.txt