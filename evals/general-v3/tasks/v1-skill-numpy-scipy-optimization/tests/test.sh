#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/fit.json ]; then
  if python3 - <<'PYEOF'
import json
import numpy as np
from scipy.optimize import curve_fit

data = np.loadtxt('/app/decay.csv', delimiter=',', skiprows=1)
t, y = data[:, 0], data[:, 1]

def model(t, a, b):
    return a * np.exp(-b * t)

popt, _ = curve_fit(model, t, y, p0=(1.0, 1.0))
a_exp, b_exp = float(popt[0]), float(popt[1])

got = json.load(open('/app/fit.json'))
a_got, b_got = float(got['a']), float(got['b'])
assert b_got > 0, 'b must be positive'
assert abs(a_got - a_exp) < 0.05, (a_got, a_exp)
assert abs(b_got - b_exp) < 0.02, (b_got, b_exp)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt