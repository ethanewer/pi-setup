#!/bin/bash
# Reference solution: compute molecular formula from a SMILES string.
set -euo pipefail

cat > /tmp/formula_ref.py <<'PY'
ELEMS = ["C","N","O","S","P","F","Cl","Br"]
def count_heavy(smi):
    counts = {e: 0 for e in ELEMS}
    i = 0
    n = len(smi)
    while i < n:
        ch = smi[i]
        if ch.isupper():
            two = smi[i:i+2]
            if two in counts:
                counts[two] += 1
                i += 2
                continue
            if ch in counts:
                counts[ch] += 1
        i += 1
    return counts

smi = open('/app/candidate.smi').read().strip()
counts = count_heavy(smi)
with open('/app/formula.txt','w') as f:
    for e in ELEMS:
        f.write(f"{e} {counts[e]}\n")
PY
python3 /tmp/formula_ref.py