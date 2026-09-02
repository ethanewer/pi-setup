#!/bin/bash
set -euo pipefail
python3 - <<'EOF'
import json
from collections import Counter
c=Counter()
for line in open('/app/logs/app1.log').read().splitlines()+open('/app/logs/app2.log').read().splitlines()+open('/app/logs/app3.log').read().splitlines():
    line=line.strip()
    if line:
        c[line.split()[1]]+=1
json.dump({k:c.get(k,0) for k in ["INFO","WARN","ERROR"]}, open('/app/summary.json','w'))
print(dict(c))
EOF