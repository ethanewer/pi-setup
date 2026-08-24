#!/bin/bash
set -euo pipefail
python3 - <<'PY'
import json, collections
tot=collections.defaultdict(int)
with open('/app/transactions.tsv') as f:
    lines=f.read().splitlines()
    header=lines[0]
    for line in lines[1:]:
        if not line.strip(): continue
        parts=line.split('\t')
        _id,cat,amt,status=parts
        if status=='active':
            tot[cat]+=int(amt)
out={k:tot[k] for k in sorted(tot)}
open('/app/report.json','w').write(json.dumps(out))
print(out)
PY
