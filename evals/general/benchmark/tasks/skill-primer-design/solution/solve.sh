#!/bin/bash
set -euo pipefail

python3 - <<'PY'
seq = open('/app/sequence.txt').read().strip()

def rc(s):
    return s.translate(str.maketrans('ACGT', 'TGCA'))[::-1]

def gc(s):
    return 100.0 * (s.count('G') + s.count('C')) / len(s)

# Forward primer: first 18+ nt window (from the start) whose GC is in range.
fwd = None
for L in range(18, 26):
    for i in range(len(seq) - L + 1):
        w = seq[i:i+L]
        if 40.0 <= gc(w) <= 60.0:
            fwd = w
            fi = i
            break
    if fwd is not None:
        break

# Reverse primer: take a window strictly after the forward match; reverse-complement it.
rev = None
for L in range(18, 26):
    for j in range(fi + len(fwd), len(seq) - L + 1):
        w = seq[j:j+L]
        if 40.0 <= gc(w) <= 60.0:
            rev = rc(w)
            break
    if rev is not None:
        break

with open('/app/primers.txt', 'w') as f:
    f.write(f'F: {fwd}\nR: {rev}\n')
print('forward', fwd, 'reverse', rev)
PY