#!/bin/bash
set -euo pipefail
cat > /app/parse_boot.py <<'PY'
import struct
data = open('/app/floppy.img', 'rb').read()
bps   = struct.unpack_from('<H', data, 11)[0]
spc   = data[13]
tot   = struct.unpack_from('<H', data, 19)[0]
spf   = struct.unpack_from('<H', data, 22)[0]
root  = struct.unpack_from('<H', data, 17)[0]
label = data[43:54].split(b'\x00')[0].decode('ascii').rstrip()
size_ok = (len(data) == bps * tot)
out = f"""BYTES_PER_SECTOR {bps}
SECTORS_PER_CLUSTER {spc}
TOTAL_SECTORS {tot}
SECTORS_PER_FAT {spf}
ROOT_ENTRIES {root}
LABEL {label}
SIZE_OK {'true' if size_ok else 'false'}
"""
open('/app/fsinfo.txt', 'w').write(out)
PY
python3 /app/parse_boot.py