FROM bench-base:python-3.12
WORKDIR /app
RUN python3 - <<'PYEOF'
import struct
L = 128
payload = bytes([k % 256 for k in range(L - 8)])
orig = b'BINF' + struct.pack('<I', L) + payload
open('/app/truncated.bin', 'wb').write(orig[:40])
PYEOF
