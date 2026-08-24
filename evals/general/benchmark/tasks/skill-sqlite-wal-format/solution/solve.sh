#!/bin/bash
set -euo pipefail

cat > /app/walinfo.py <<'PY'
import struct

with open('/app/data.db-wal', 'rb') as f:
    b = f.read()

def u32(off):
    return struct.unpack('>I', b[off:off+4])[0]

magic = u32(0)
version = u32(4)
page_size = u32(8)
first_frame_page = u32(32)
first_frame_db_size = u32(36)

with open('/app/walinfo.txt', 'w') as f:
    f.write(f"magic=0x{magic:08x}\n")
    f.write(f"version={version}\n")
    f.write(f"page_size={page_size}\n")
    f.write(f"first_frame_page={first_frame_page}\n")
    f.write(f"first_frame_db_size={first_frame_db_size}\n")
PY

python3 /app/walinfo.py