#!/bin/bash
set -euo pipefail

cat > /app/extract.py <<'PYEOF'
import gzip, bz2, lzma

with open('/app/archive.bin', 'rb') as f:
    data = f.read()

def extract(buf):
    if buf[:2] == b'\x1f\x8b':
        return gzip.decompress(buf)
    if buf[:3] == b'BZh':
        return bz2.decompress(buf)
    if buf[:6] == b'\xfd7zXZ\x00':
        return lzma.decompress(buf)
    return buf

out = extract(data)
with open('/app/extracted.txt', 'wb') as f:
    f.write(out)
PYEOF

python3 /app/extract.py