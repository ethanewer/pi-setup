#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/header.txt ]; then
  python3 - <<'PY' && reward=1
import struct

with open('/app/data.db', 'rb') as f:
    raw = f.read()
ps = struct.unpack('>H', raw[16:18])[0]
if ps == 1:
    ps = 65536
pc = struct.unpack('>I', raw[28:32])[0]
assert pc > 1, pc

lines = [ln.strip() for ln in open('/app/header.txt') if ln.strip()]
assert len(lines) == 2, lines
ns = None
nc = None
for ln in lines:
    if ln.startswith('page_size='):
        ns = int(ln[len('page_size='):])
    elif ln.startswith('page_count='):
        nc = int(ln[len('page_count='):])
assert ns == ps, (ns, ps)
assert nc == pc, (nc, pc)
PY
fi
echo "$reward" > /logs/verifier/reward.txt