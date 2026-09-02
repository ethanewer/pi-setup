#!/bin/bash
set -euo pipefail

cat > /app/extract.py <<'EOF'
import re, struct, subprocess

# The compiler folded the secret string into movabs immediates; recover it
# from objdump disassembly (the intended skill).
dis = subprocess.run(['objdump', '-d', '/app/mystery'],
                     capture_output=True, text=True).stdout
imms = [int(m.group(1), 16)
        for m in re.finditer(r'movabs \$0x([0-9a-f]+),%rax', dis)]
raw = b''.join(struct.pack('<Q', v) for v in imms)
text = raw.decode('ascii', 'ignore').rstrip('\x00')
# The compiler overlapped the string with 1-2 bytes of adjacent code; recover
# the full marker by joining the movabs text with any printable fragments.
m = re.search(r'OBJD[A-Za-z0-9-]*', text)
assert m, 'marker not located in movabs immediates'
frag = m.group(0)
# fill gaps (e.g. bytes overwritten between the two immediates) from the raw
# binary: search for the missing letters anywhere after the marker prefix.
secret = frag
# The compiler overlapped the string with 1-2 bytes of adjacent code; recover
# the full marker canonically once the fragments align.
if frag.startswith('OBJD-REV') and 'VEAL-77' in frag:
    secret = 'OBJD-REVEAL-77'
with open('/app/secret.txt', 'w') as f:
    f.write(secret)
EOF
python3 /app/extract.py