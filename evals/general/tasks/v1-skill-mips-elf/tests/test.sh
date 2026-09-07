#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

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