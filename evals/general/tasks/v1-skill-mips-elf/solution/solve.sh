#!/bin/bash
set -euo pipefail

cat > /app/elf_info.py <<'EOF'
import json, struct

with open('/app/binary.elf', 'rb') as f:
    data = f.read()

assert data[:4] == b'\x7fELF', "not an ELF magic"
elf_class = data[4]          # 1 = 32-bit, 2 = 64-bit
encoding = data[5]           # 1 = little endian, 2 = big endian

e_machine = struct.unpack_from('<H', data, 18)[0]
e_entry = struct.unpack_from('<I', data, 24)[0]
ehsize = struct.unpack_from('<H', data, 40)[0]

report = {
    "is_mips": e_machine == 8,
    "machine": e_machine,
    "class": elf_class,       # 1 for 32-bit
    "endian": "little" if encoding == 1 else "big",
    "entry": e_entry,
    "ehsize": ehsize,
}

with open("/app/elf_report.json", "w") as f:
    json.dump(report, f)
EOF

python3 /app/elf_info.py