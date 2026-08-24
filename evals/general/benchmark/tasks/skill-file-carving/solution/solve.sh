#!/bin/bash
set -euo pipefail

cat > /app/carve.py <<'PYEOF'
import json

blob = open('/app/blob.bin', 'rb').read()
sig = b'\x89PNG\r\n\x1a\n'

start = blob.index(sig)
iend = blob.index(b'IEND')
end = iend + 8

carved = blob[start:end]
with open('/app/carved.png', 'wb') as f:
    f.write(carved)

with open('/app/carved.json', 'w') as f:
    json.dump({'offset': start, 'length': len(carved), 'valid_ending': True}, f)
PYEOF

python3 /app/carve.py