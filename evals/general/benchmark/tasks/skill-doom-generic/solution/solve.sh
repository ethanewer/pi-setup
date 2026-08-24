#!/bin/bash
set -euo pipefail
cat > /app/parse_wad.py <<'PY'
import struct
data = open('/app/doom.wad', 'rb').read()
magic = data[0:4].decode('ascii')
n = struct.unpack_from('<I', data, 4)[0]
diroff = struct.unpack_from('<I', data, 8)[0]
entries = []
for i in range(n):
    off = diroff + i * 16
    fpos = struct.unpack_from('<I', data, off)[0]
    size = struct.unpack_from('<I', data, off + 4)[0]
    name = data[off+8:off+16].split(b'\x00')[0].decode('ascii').strip()
    entries.append((fpos, size, name))
biggest = entries[0][2]
best_size = entries[0][1]
for _, size, name in entries:
    if size > best_size:
        best_size, biggest = size, name
with open('/app/wadinfo.txt', 'w') as f:
    f.write(f"TYPE {magic}\nLUMPCOUNT {n}\nBIGGEST {biggest}\n")
PY
python3 /app/parse_wad.py