#!/bin/bash
set -euo pipefail
cat > /app/parse_bin.py <<'PYEOF'
import struct, json
data = open('/app/data.bin', 'rb').read()
assert data[:4] == b'DPAR', 'bad magic'
N = struct.unpack('<I', data[4:8])[0]
assert len(data) == 8 + N * 6, 'length mismatch'
sum0 = 0; sum1 = 0; x = 0
off = 8
for i in range(N):
    typ, val = struct.unpack_from('<Hi', data, off)
    off += 6
    if typ == 0: sum0 += val
    elif typ == 1: sum1 += val
    x ^= val
json.dump({'count': N, 'sum_type0': sum0, 'sum_type1': sum1, 'xor_all': x}, open('/app/parsed.json', 'w'))
PYEOF
python3 /app/parse_bin.py
