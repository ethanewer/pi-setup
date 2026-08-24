#!/bin/bash
set -euo pipefail
cat > /app/unpack.py <<'PYEOF'
data = open('/app/packed.bin', 'rb').read()
bits = []
for byte in data:
    for shift in range(7, -1, -1):
        bits.append((byte >> shift) & 1)
vals = []
i = 0
while i + 3 <= len(bits):
    v = (bits[i] << 2) | (bits[i+1] << 1) | bits[i+2]
    vals.append(v)
    i += 3
with open('/app/decoded.txt', 'w') as f:
    for v in vals:
        f.write(str(v) + chr(10))
PYEOF
python3 /app/unpack.py
