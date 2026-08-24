#!/bin/bash
set -euo pipefail
cat > /app/decompress.py <<'PYEOF'
out = bytearray()
with open('/app/packed.dat') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        count, hx = line.split()
        out.extend(bytes([int(hx, 16)]) * int(count))
with open('/app/unpacked.txt', 'wb') as f:
    f.write(bytes(out))
PYEOF
python3 /app/decompress.py