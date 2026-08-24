#!/bin/bash
mkdir -p /logs/verifier
reward=0

if python3 - <<'PY'
import struct
data = open('/app/doom.wad', 'rb').read()
magic = data[0:4].decode('ascii')
n = struct.unpack_from('<I', data, 4)[0]
diroff = struct.unpack_from('<I', data, 8)[0]
entries = []
for i in range(n):
    off = diroff + i * 16
    size = struct.unpack_from('<I', data, off + 4)[0]
    name = data[off+8:off+16].split(b'\x00')[0].decode('ascii').strip()
    entries.append((size, name))
biggest = entries[0][1]
bsz = entries[0][0]
for size, name in entries:
    if size > bsz:
        bsz, biggest = size, name
expected = f"TYPE {magic}\nLUMPCOUNT {n}\nBIGGEST {biggest}\n"
assert open('/app/wadinfo.txt').read() == expected, (open('/app/wadinfo.txt').read(), expected)
PY
then
  reward=1
fi

echo "$reward" > /logs/verifier/reward.txt