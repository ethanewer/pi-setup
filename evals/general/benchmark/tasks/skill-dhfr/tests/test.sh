#!/bin/bash
mkdir -p /logs/verifier
reward=0
if python3 - <<'PYEOF'
ELEMS = ['C', 'N', 'O', 'S', 'P', 'F', 'Cl', 'Br']
smi = open('/app/candidate.smi').read().strip()
counts = {e: 0 for e in ELEMS}
i = 0
n = len(smi)
while i < n:
    ch = smi[i]
    if ch.isupper():
        two = smi[i:i + 2]
        if two in counts:
            counts[two] += 1
            i += 2
            continue
        if ch in counts:
            counts[ch] += 1
    i += 1
lines = [x for x in open('/app/formula.txt').read().splitlines() if x]
assert len(lines) == 8, len(lines)
for e, ln in zip(ELEMS, lines):
    parts = ln.split()
    assert parts[0] == e and int(parts[1]) == counts[e], (e, ln, counts[e])
PYEOF
then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt