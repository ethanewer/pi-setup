#!/bin/bash
# Oracle: decode the mixed-endian fields in /app/data.bin and write the
# 32-bit address 0xDEADBEEF to /app/out.bin in little-endian byte order.
set -euo pipefail
python3 - <<'PYEOF'
import struct

data = open('/app/data.bin', 'rb').read()
a = struct.unpack_from('<I', data, 0x00)[0]  # uint32 LE
b = struct.unpack_from('>H', data, 0x04)[0]  # uint16 BE
c = struct.unpack_from('<Q', data, 0x06)[0]  # uint64 LE

with open('/app/answer.txt', 'w') as out:
    out.write('%d\n%d\n%d\n' % (a, b, c))

with open('/app/out.bin', 'wb') as out:
    out.write(struct.pack('<I', 0xDEADBEEF))
PYEOF