#!/bin/bash
set -euo pipefail
cat > /app/sum_bin.py <<'PY'
import struct, array
with open('/app/numbers.bin','rb') as f:
    data = f.read()
vals = struct.unpack('<%di' % (len(data)//4), data)
open('/app/sum.txt','w').write(str(sum(vals)))
PY
python3 /app/sum_bin.py
echo "wrote /app/sum.txt = $(cat /app/sum.txt)"
