#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
reward=0
if [ -f /app/molecule.json ]; then
  if python3 - <<'PYEOF'
import json
rm = {'A': 71.03711, 'C': 103.00919, 'E': 129.04259}
water = 18.01056
peptide = 'ACE'
exp = sum(rm[ch] for ch in peptide) + water
got = json.load(open('/app/molecule.json'))
assert got.get('peptide') == peptide
assert abs(float(got.get('mass_da')) - exp) < 1e-3, (got, exp)
PYEOF
then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt