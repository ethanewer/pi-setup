#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/names.txt ]; then
  if python3 - <<'PYEOF'
import struct
data = open('/app/records.bin','rb').read()
rec = struct.Struct('<I30s')
names = []
for off in range(0, len(data), rec.size):
    rid, raw = struct.unpack_from('<I30s', data, off)
    names.append(raw.decode('ascii').rstrip('\x00'))
exp = ''.join(n + '\n' for n in names)
got = open('/app/names.txt', encoding='utf-8').read()
assert got == exp, (got, exp)
PYEOF
then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt