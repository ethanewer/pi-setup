#!/bin/bash
set -euo pipefail
python3 - <<'PY'
dna=open('/app/dna.txt').read().strip()
mut=[]
for line in open('/app/mutations.txt'):
    line=line.strip()
    if not line: continue
    i,old,new=line.split()
    mut.append((int(i),old,new))
arr=list(dna)
for i,old,new in mut:
    assert arr[i]==old, (i,old,arr[i])
    arr[i]=new
open('/app/mutated.txt','w').write(''.join(arr))
print('mutated:', ''.join(arr))
PY
