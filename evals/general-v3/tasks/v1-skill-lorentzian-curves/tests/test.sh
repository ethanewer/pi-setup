#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/answer.json ]; then
  if python3 - <<'PYEOF'
import json, math
got = json.load(open('/app/answer.json'))
exp_fwhm = 1.6
exp_peak = 2.0 / (math.pi * 0.8)
assert abs(float(got.get("fwhm", -1)) - exp_fwhm) <= 1e-6, (got, exp_fwhm)
assert abs(float(got.get("peak_height", -1)) - exp_peak) <= 0.001, (got, exp_peak)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt