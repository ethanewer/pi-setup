#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/answer.txt ]; then
  if python3 - <<'PYEOF'
import json

with open('/app/pip/3abc.json') as f:
    d = json.load(f)
residues = d['struct']['n_residues']
atoms = sum(e['n_atoms'] for e in d['entities'])
expected = f"atoms {atoms} residues {residues}"

with open('/app/answer.txt') as f:
    got = f.read().strip()
assert got == expected, (got, expected)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt