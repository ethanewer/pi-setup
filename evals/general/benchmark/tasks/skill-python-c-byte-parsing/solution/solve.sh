#!/bin/bash
set -euo pipefail
python3 - <<'PY'
import struct
data=open('/app/records.bin','rb').read()
rec=struct.Struct('<I30s')
names=[]
for off in range(0,len(data),rec.size):
    rid, raw = struct.unpack_from('<I30s', data, off)
    names.append(raw.decode('ascii').rstrip('\x00'))
with open('/app/names.txt','w') as f:
    for n in names:
        f.write(n+'\n')
print(names)
PY
