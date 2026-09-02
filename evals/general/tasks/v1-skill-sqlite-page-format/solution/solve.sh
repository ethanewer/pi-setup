#!/bin/bash
set -euo pipefail

cat > /app/pageinfo.py <<'PY'
import struct

with open('/app/data.db', 'rb') as f:
    raw = f.read()

page_size = struct.unpack('>H', raw[16:18])[0]
if page_size == 1:
    page_size = 65536
page_count = struct.unpack('>I', raw[28:32])[0]

with open('/app/header.txt', 'w') as f:
    f.write(f"page_size={page_size}\n")
    f.write(f"page_count={page_count}\n")
PY

python3 /app/pageinfo.py