#!/bin/bash
set -euo pipefail
python3 - <<'PY'
data = open('/app/evidence.bin', 'rb').read()
assert data[:8] == b'\x89PNG\r\n\x1a\n', "not a PNG"
# everything after the IEND chunk end is appended data
iend = data.rfind(b'IEND')
assert iend != -1
# IEND chunk: 4 len + 4 tag + 0 data + 4 crc
end = iend + 4 + 4 + 0 + 4
tail = data[end:].decode('latin1')
token = tail.strip().split(':', 1)[1].strip()
open('/app/file_type.txt', 'w').write('png\n')
open('/app/flag.txt', 'w').write(token + '\n')
PY