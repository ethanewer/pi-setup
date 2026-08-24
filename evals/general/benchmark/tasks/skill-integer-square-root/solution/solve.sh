#!/bin/bash
set -euo pipefail
python3 - <<'EOF'
import math
n = int(open('/app/number.txt').read().strip())
k = math.isqrt(n)
with open('/app/sqrt_output.txt','w') as f:
    f.write(str(k) + '\n')
print("wrote", k)
EOF