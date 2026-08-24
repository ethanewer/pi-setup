FROM bench-base:python-3.12

WORKDIR /app

# Build a valid 1x1 PNG and append a hidden token after its IEND chunk.
RUN python3 - <<'PY'
import struct, zlib

def chunk(typ, data):
    c = struct.pack('>I', len(data)) + typ + data
    c += struct.pack('>I', zlib.crc32(typ + data) & 0xFFFFFFFF)
    return c

png = b'\x89PNG\r\n\x1a\n'
png += chunk(b'IHDR', struct.pack('>IIBBBBB', 1, 1, 8, 2, 0, 0, 0))
png += chunk(b'IDAT', zlib.compress(b'\x00\x00\x00\x00'))
png += chunk(b'IEND', b'')

hidden = b'\nHIDDEN-TOKEN:df-token-8f3b21e9\n'
open('/app/evidence.bin', 'wb').write(png + hidden)
PY