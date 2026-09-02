FROM bench-base:python-3.12
WORKDIR /app
RUN python3 - <<'PYEOF'
import struct
recs = []
for i in range(24):
    typ = i % 2
    val = (i * 37 + 3) % 1000
    recs.append((typ, val))
bv = b'DPAR' + struct.pack('<I', len(recs))
for typ, val in recs:
    bv += struct.pack('<H', typ) + struct.pack('<i', val)
open('/app/data.bin', 'wb').write(bv)
PYEOF
