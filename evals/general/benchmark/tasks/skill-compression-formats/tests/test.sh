#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/extracted.txt ]; then
  if python3 - <<'PYEOF'
import gzip, bz2, lzma

with open('/app/archive.bin', 'rb') as f:
    data = f.read()

def decompress(buf):
    if buf[:2] == b'\x1f\x8b':
        return gzip.decompress(buf)
    if buf[:3] == b'BZh':
        return bz2.decompress(buf)
    if buf[:6] == b'\xfd7zXZ\x00':
        return lzma.decompress(buf)
    return buf

expected = decompress(data)
got = open('/app/extracted.txt', 'rb').read()
if got.strip(b'\n') != expected.strip(b'\n'):
    raise SystemExit((got, expected))
print("PASS"); raise SystemExit(0)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt