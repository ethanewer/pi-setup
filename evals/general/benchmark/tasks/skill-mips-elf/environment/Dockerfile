FROM bench-base:python-3.12

WORKDIR /app

# Build a minimal 32-bit little-endian MIPS (EM_MIPS=8) ELF executable header.
RUN python3 - <<'PY'
import struct
ident = bytes([0x7f, 0x45, 0x4c, 0x46, 0x01, 0x01, 0x01, 0x00,
               0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
# e_type=2(EXEC), e_machine=8(MIPS), e_version=1
fh = struct.pack('<HHI', 2, 8, 1)
# e_entry = 0x00400000
entry = struct.pack('<I', 0x00400000)
# e_phoff, e_shoff, e_flags, e_ehsize, e_phentsize, e_phnum, e_shentsize, e_shnum, e_shstrndx
rest = struct.pack('<IIIHHHHHH', 0, 0, 0, 52, 0, 0, 0, 0, 0)
with open('/app/binary.elf', 'wb') as f:
    f.write(ident + fh + entry + rest)
PY

# Also write a copy with a different extension as a decoy to ensure path-name independence.
RUN cp /app/binary.elf /app/mips_program