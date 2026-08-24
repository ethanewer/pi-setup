#!/bin/bash
set -euo pipefail

python3 - <<'PY'
import struct, zlib

def chunk(typ, payload):
    return struct.pack('>I', len(payload)) + typ + payload + \
           struct.pack('>I', zlib.crc32(typ + payload))

sig = b'\x89PNG\r\n\x1a\n'
ihdr = struct.pack('>IIBBBBB', 4, 4, 8, 2, 0, 0, 0)   # W=4 H=4 bd=8 ct=2 cm=0 fm=0 il=0
row = b'\x00' + b'\xff\x00\x00' * 4                   # filter None + 4 red pixels
raw = row * 4                                          # 4 scanlines = 52 bytes
png = sig + chunk(b'IHDR', ihdr) + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b'')
open('/app/solid.png', 'wb').write(png)
print('png written', len(png))
PY