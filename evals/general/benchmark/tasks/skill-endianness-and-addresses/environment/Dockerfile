FROM bench-base:python-3.12

WORKDIR /app

# A 14-byte fixture with mixed endianness:
#   offset 0x00: uint32 LE = 0x01020304 -> 04 03 02 01
#   offset 0x04: uint16 BE = 0x1122       -> 11 22
#   offset 0x06: uint64 LE = 0x00000000DEADBEEF -> EF BE AD DE 00 00 00 00
RUN python3 - <<'PYEOF'
open('/app/data.bin', 'wb').write(bytes([
    0x04, 0x03, 0x02, 0x01,        # uint32 little-endian
    0x11, 0x22,                      # uint16 big-endian
    0xEF, 0xBE, 0xAD, 0xDE, 0x00, 0x00, 0x00, 0x00,  # uint64 little-endian
]))
print('wrote data.bin')
PYEOF