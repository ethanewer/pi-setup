FROM bench-base:python-3.12
WORKDIR /app
RUN python3 - <<'PYEOF'
vals = [(i * 5 + 1) % 7 for i in range(24)]
bits = []
for v in vals:
    for b in (2, 1, 0):
        bits.append((v >> b) & 1)
out = bytearray()
for c in range(0, len(bits), 8):
    byte = 0
    for j in range(8):
        b = bits[c + j] if c + j < len(bits) else 0
        byte = (byte << 1) | b
    out.append(byte)
open('/app/packed.bin', 'wb').write(bytes(out))
PYEOF
