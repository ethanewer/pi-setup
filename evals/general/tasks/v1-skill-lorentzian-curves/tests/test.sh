#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

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