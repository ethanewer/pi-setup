#!/bin/bash
set -euo pipefail
python3 - <<'EOF'
import json
lst=json.load(open('/app/input.json'))
kept=[x for x in lst if x>=10]
seen=set(); uniq=[]
for x in kept:
    if x not in seen:
        seen.add(x); uniq.append(x)
res=[z*3 for z in sorted(uniq)]
json.dump(res, open('/app/result.json','w'))
print(res)
EOF