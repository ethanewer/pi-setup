FROM bench-base:python-3.12
WORKDIR /app
RUN python3 - <<'PYEOF'
import struct, zlib

def chunk(typ, data):
    return struct.pack('>I', len(data)) + typ + data + struct.pack('>I', zlib.crc32(typ + data) & 0xffffffff)

def make_png(seed):
    w, h = 16, 16
    rows = []
    for y in range(h):
        row = bytearray()
        for x in range(w):
            row += bytes([(x * seed + y * 13) % 256 & 0xFF])
            row += bytes([(x * 7 + y * seed) % 256])
            row += bytes([(x * 11 + y * 3) % 256])
        rows.append(b'\x00' + bytes(row))
    idat = zlib.compress(b''.join(rows))
    ihdr = struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', ihdr) + chunk(b'IDAT', idat) + chunk(b'IEND', b'')

png = None
for seed in range(1, 40):
    cand = make_png(seed)
    if cand.count(b'IEND') == 1 and cand.count(b'\x89PNG\r\n\x1a\n') == 1:
        png = cand
        break
assert png is not None, 'no clean PNG found'

blob = (b'\x00RAWMEM7\xff\xfe\x2b\x99\x00\x11binary junk fills the buffer ....'
        + png
        + b'trailing garbage bytes that are not part of any file <-##')
open('/app/blob.bin', 'wb').write(blob)
PYEOF