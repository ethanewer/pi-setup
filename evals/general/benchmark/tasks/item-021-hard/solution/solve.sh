#!/bin/bash
set -euo pipefail

python3 - <<'PY'
from Bio import SeqIO

rec = next(SeqIO.parse('/app/plasmid.fa', 'fasta'))
S = str(rec.seq)
L = len(S)
line = open('/app/edit.txt').read().split()
p = int(line[0])
P = line[1].strip()

M = S[:p] + P + S[p:L]

REV = {'A': 'T', 'T': 'A', 'G': 'C', 'C': 'G'}
def rc(x):
    return ''.join(REV[c] for c in reversed(x))

def preceding(pos, k):
    idx = [(pos - 1 - j) % L for j in range(k)]
    return ''.join(S[i] for i in reversed(idx))

F = preceding(p, 10) + P[:10]
assert len(F) == 20, F

win = M[p-8:p+12]
R = rc(win)

def gcfrac(x):
    return sum(1 for c in x if c in 'GC') / len(x)

ok = (18 <= len(F) <= 25 and 18 <= len(R) <= 25 and
      0.40 <= gcfrac(F) <= 0.60 and 0.40 <= gcfrac(R) <= 0.60)
open('/app/validation.txt', 'w').write(('OK\n' if ok else 'FAIL\n'))

with open('/app/plasmid_mutated.fa', 'w') as f:
    f.write('>circular_plasmid\n' + M + '\n')

with open('/app/primers.fa', 'w') as f:
    f.write('>forward\n' + F + '\n>reverse\n' + R + '\n')

print('M', M, len(M))
print('F', F, len(F), round(gcfrac(F), 2))
print('R', R, len(R), round(gcfrac(R), 2))
print('validation', 'OK' if ok else 'FAIL')
PY