#!/bin/bash
set -euo pipefail
python3 - <<'PY'
import json, math
jobs=[]
for line in open('/app/jobs.txt'):
    line=line.strip()
    if not line or line.startswith('#'): continue
    jid,arr,bur=line.split('\t')
    jobs.append((jid,int(arr),int(bur)))
work=sorted(enumerate(jobs), key=lambda t:(t[1][1], t[0]))
time=0; waits=[]
for idx,(jid,arr,bur) in work:
    start=max(time,arr)
    comp=start+bur
    waits.append(start-arr)
    time=comp
avg=round(sum(waits)/len(waits),2)
out={"jobs": len(jobs), "avg_wait": avg, "completion_time": time}
open('/app/queue.json','w').write(json.dumps(out))
print(out)
PY
