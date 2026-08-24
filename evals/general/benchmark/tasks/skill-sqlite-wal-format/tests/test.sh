#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/walinfo.txt ]; then
  python3 - <<'PY' && reward=1
import struct

with open('/app/data.db-wal', 'rb') as f:
    b = f.read()
u32 = lambda off: struct.unpack('>I', b[off:off+4])[0]

expected = {
    'magic': f"0x{u32(0):08x}",
    'version': str(u32(4)),
    'page_size': str(u32(8)),
    'first_frame_page': str(u32(32)),
    'first_frame_db_size': str(u32(36)),
}

lines = [ln.strip() for ln in open('/app/walinfo.txt') if ln.strip()]
assert len(lines) == 5, lines
got = {}
for ln in lines:
    key, _, val = ln.partition('=')
    got[key.strip()] = val.strip()
assert got == expected, (got, expected)
PY
fi
echo "$reward" > /logs/verifier/reward.txt