#!/bin/bash
mkdir -p /logs/verifier
reward=0

if python3 - <<'PY'
import struct
data = open('/app/floppy.img', 'rb').read()
bps   = struct.unpack_from('<H', data, 11)[0]
spc   = data[13]
tot   = struct.unpack_from('<H', data, 19)[0]
spf   = struct.unpack_from('<H', data, 22)[0]
root  = struct.unpack_from('<H', data, 17)[0]
label = data[43:54].split(b'\x00')[0].decode('ascii').rstrip()
expected = f"""BYTES_PER_SECTOR {bps}
SECTORS_PER_CLUSTER {spc}
TOTAL_SECTORS {tot}
SECTORS_PER_FAT {spf}
ROOT_ENTRIES {root}
LABEL {label}
SIZE_OK {'true' if len(data) == bps*tot else 'false'}"""

got = open('/app/fsinfo.txt').read().strip()
assert got == expected.strip(), (got, expected)
PY
then
  reward=1
fi

echo "$reward" > /logs/verifier/reward.txt