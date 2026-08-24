#!/bin/bash
mkdir -p /logs/verifier
reward=0
if python3 - <<'PYEOF'
import struct, zlib
data = open('/app/solid.png', 'rb').read()
assert data[:8] == b'\x89PNG\r\n\x1a\n', data[:8]
pos = 8
chunks = {}
while pos < len(data):
    length = struct.unpack('>I', data[pos:pos+4])[0]
    typ = data[pos+4:pos+8]
    payload = data[pos+8:pos+8+length]
    crc = struct.unpack('>I', data[pos+8+length:pos+12+length])[0]
    assert crc == zlib.crc32(typ + payload) & 0xffffffff
    if typ == b'IHDR':
        W, H, depth, ctype, comp, filt, inter = struct.unpack('>IIBBBBB', payload)
        assert (W, H, depth, ctype) == (4, 4, 8, 2), (W, H, depth, ctype)
    elif typ == b'IDAT':
        chunks.setdefault('idat', b'' + payload)
    elif typ == b'IEND':
        assert length == 0
    pos += 12 + length
raw = zlib.decompress(chunks['idat'])
assert len(raw) == 52
for y in range(4):
    base = y * 13
    assert raw[base] == 0
    assert raw[base+1:base+13] == b'\xff\x00\x00' * 4, (y, raw[base+1:base+13])
PYEOF
then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt