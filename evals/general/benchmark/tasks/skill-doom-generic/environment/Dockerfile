FROM bench-base:python-3.12

WORKDIR /app

# Create a minimal IWAD: 3 lumps, MAP01 being the largest.
RUN python3 - <<'PY'
import struct
lumps = [
    (20, b'M_START'),
    (40, b'MAP01'),
    (20, b'M_END'),
]
N = len(lumps)
dir_offset = 12
pos = dir_offset + N * 16
entries = []
for size, name in lumps:
    entries.append((pos, size, name))
    pos += size
buf = bytearray()
buf += b'IWAD'
buf += struct.pack('<I', N)
buf += struct.pack('<I', dir_offset)
for fp, size, name in entries:
    buf += struct.pack('<I', fp)
    buf += struct.pack('<I', size)
    buf += name.ljust(8, b'\x00')
for size, name in lumps:
    buf += bytes([0xAA]) * size
open('/app/doom.wad', 'wb').write(bytes(buf))
PY