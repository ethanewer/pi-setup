#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

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