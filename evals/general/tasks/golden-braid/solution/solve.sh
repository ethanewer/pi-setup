#!/bin/bash
# Real oracle for golden-braid.
# Writes the assembly program to /app/solve.py, then RUNS it on
# /app/reads.txt to produce /app/contig.txt. Does actual work; never reads
# /tests and never cats precomputed answers.
set -eu

cat > /app/solve.py <<'PY'
import sys


def read_fasta(path):
    reads = []
    cur = ''
    for line in open(path):
        line = line.strip()
        if not line:
            continue
        if line.startswith('>'):
            if cur:
                reads.append(cur)
            cur = ''
        else:
            cur += line
    if cur:
        reads.append(cur)
    return reads


def overlap(a, b):
    m = min(len(a), len(b))
    for t in range(m, 0, -1):
        if a[-t:] == b[:t]:
            return t
    return 0


def assemble(reads):
    if not reads:
        return ''
    active = []
    for r in reads:
        if r not in active:
            active.append(r)
    changed = True
    while changed:
        changed = False
        keep = []
        for i, r in enumerate(active):
            contained = False
            for j, o in enumerate(active):
                if i != j and r in o:
                    contained = True
                    break
            if not contained:
                keep.append(r)
        if len(keep) != len(active):
            active = keep
            changed = True
    segs = active
    while len(segs) > 1:
        cands = []
        for i in range(len(segs)):
            for j in range(len(segs)):
                if i == j:
                    continue
                a, b = segs[i], segs[j]
                L = overlap(a, b)
                cands.append((L, a + b[L:], i, j))
        maxL = max(c[0] for c in cands)
        cands = [c for c in cands if c[0] == maxL]
        minM = min(c[1] for c in cands)
        cands = [c for c in cands if c[1] == minM]
        cands.sort(key=lambda c: (c[2], c[3]))
        L, merged, i, j = cands[0]
        new_segs = []
        for k, s in enumerate(segs):
            if k == i or k == j:
                continue
            new_segs.append(s)
        new_segs.append(merged)
        segs = new_segs
    return segs[0]


if __name__ == '__main__':
    inp, out = sys.argv[1], sys.argv[2]
    reads = read_fasta(inp)
    result = assemble(reads)
    with open(out, 'w') as f:
        f.write(result + '\n')
PY

python3 /app/solve.py /app/reads.txt /app/contig.txt