#!/bin/bash
set -euo pipefail
python3 - <<'PY'
rows=[]
for line in open('/app/names.txt'):
    line=line.strip()
    if not line: continue
    name,val=line.split('=')
    v=int(val)
    if v%2==0:
        rows.append((name,v))
rows.sort(key=lambda t:t[0])
with open('/app/out.txt','w') as f:
    for name,v in rows:
        f.write('%s:%d\n'%(name,v))
print('wrote out.txt')
PY
