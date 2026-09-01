#!/usr/bin/env python3
import json
import numpy as np
import scipy.optimize as so

data = np.genfromtxt('/app/raman.csv', delimiter=',', names=True)
x = data['wavenumber_cm1'].astype(float)
y = data['intensity'].astype(float)

def lor(w, A, c, g):
    return A * g * g / ((w - c) ** 2 + g * g)

def model(w, A0, c0, g0, A1, c1, g1, A2, c2, g2):
    return lor(w, A0, c0, g0) + lor(w, A1, c1, g1) + lor(w, A2, c2, g2)

p0 = [80, 540, 18, 60, 585, 12, 60, 720, 10]
lo = [0, 500, 1, 0, 520, 1, 0, 650, 1]
hi = [300, 600, 60, 300, 600, 60, 300, 800, 60]
popt, _ = so.curve_fit(model, x, y, p0=p0, bounds=(lo, hi), maxfev=50000)

peaks = sorted([
    {'center': float(popt[1]), 'height': float(popt[0]), 'width': float(popt[2])},
    {'center': float(popt[4]), 'height': float(popt[3]), 'width': float(popt[5])},
    {'center': float(popt[7]), 'height': float(popt[6]), 'width': float(popt[8])},
], key=lambda p: p['center'])

resid = y - model(x, *popt)
out = {
    'peaks': peaks,
    'residual_rms': float(np.sqrt(np.mean(resid ** 2))),
}
json.dump(out, open('/app/fit.json', 'w'), indent=2)
print('wrote fit.json', peaks)