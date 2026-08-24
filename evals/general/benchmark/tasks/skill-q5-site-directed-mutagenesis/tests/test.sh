#!/bin/bash
mkdir -p /logs/verifier
reward=0
if python3 - <<'PYEOF'
import json
dna = open('/app/dna.txt').read().strip()
mut = []
for line in open('/app/mutations.txt'):
    line = line.strip()
    if not line:
        continue
    i, old, new = line.split()
    mut.append((int(i), old, new))
arr = list(dna)
for i, old, new in mut:
    assert arr[i] == old, (i, old, arr[i])
    arr[i] = new
expected = ''.join(arr)
got = open('/app/mutated.txt').read().strip()
assert got == expected, (got, expected)
PYEOF
then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt