#!/bin/bash
set -euo pipefail

cat > /app/compare.py <<'PY'
import sys

def load(path):
    toks = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            toks += line.split()
    assert toks[0] == 'P3', 'not P3'
    w, h, mx = int(toks[1]), int(toks[2]), int(toks[3])
    vals = [int(x) for x in toks[4:4 + w*h*3]]
    return w, h, vals

wa, ha, pa = load('/app/a.ppm')
wb, hb, pb = load('/app/b.ppm')
n_pix = wa * ha
ndiff = 0
maxd = 0
for i in range(n_pix):
    b = i * 3
    if pa[b] != pb[b] or pa[b+1] != pb[b+1] or pa[b+2] != pb[b+2]:
        ndiff += 1
for c in range(n_pix * 3):
    d = abs(pa[c] - pb[c])
    if d > maxd:
        maxd = d
print(f'{ndiff} {maxd}')
PY

python3 /app/compare.py > /app/diff.txt