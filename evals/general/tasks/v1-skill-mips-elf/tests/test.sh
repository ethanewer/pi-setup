#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/elf_report.json ]; then
  if python3 - <<'PYEOF'
import json, struct
with open('/app/binary.elf', 'rb') as f:
    data = f.read()
assert data[:4] == b'\x7fELF'
e_machine = struct.unpack_from('<H', data, 18)[0]
e_entry = struct.unpack_from('<I', data, 24)[0]
ehsize = struct.unpack_from('<H', data, 40)[0]
exp = {
    "is_mips": e_machine == 8,
    "machine": e_machine,
    "class": data[4],
    "endian": "little" if data[5] == 1 else "big",
    "entry": e_entry,
    "ehsize": ehsize,
}
got = json.load(open('/app/elf_report.json'))
assert got == exp, (got, exp)
PYEOF
then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt