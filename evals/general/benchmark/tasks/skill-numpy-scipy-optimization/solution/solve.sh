#!/bin/bash
# Oracle solution for skill-numpy-scipy-optimization.
set -euo pipefail

cat > /app/fit.py <<'PYEOF'
import json
import numpy as np
from scipy.optimize import curve_fit

data = np.loadtxt('/app/decay.csv', delimiter=',', skiprows=1)
t, y = data[:, 0], data[:, 1]

def model(t, a, b):
    return a * np.exp(-b * t)

popt, _ = curve_fit(model, t, y, p0=(1.0, 1.0))
a, b = popt
json.dump({'a': round(float(a), 4), 'b': round(float(b), 4)},
          open('/app/fit.json', 'w'))
PYEOF

python3 /app/fit.py