#!/bin/bash
set -euo pipefail
python3 - <<'EOF'
sbox=[6,2,5,0,3,1,7,4]
a,b=5,7
cnt=sum(1 for i in range(8) if (bin(i&a).count('1')%2)==(bin(sbox[i]&b).count('1')%2))
import json
json.dump({"count":cnt}, open('/app/answer.json','w'))
print("count:",cnt)
EOF