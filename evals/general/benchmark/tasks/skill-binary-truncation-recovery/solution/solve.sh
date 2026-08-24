#!/bin/bash
set -euo pipefail
cat > /app/recover.py <<'PYEOF'
import struct
data = open('/app/truncated.bin', 'rb').read()
assert data[:4] == b'BINF'
L = struct.unpack('<I', data[4:8])[0]
head_len = 8
present = bytearray(data)
need = L - len(data)
for k in range(len(data) - head_len, L - head_len):
    present.append(k % 256)
assert len(present) == L, (len(present), L)
open('/app/recovered.bin', 'wb').write(bytes(present))
PYEOF
python3 /app/recover.py
