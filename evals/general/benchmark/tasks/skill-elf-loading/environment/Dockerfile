FROM bench-base:python-3.12

WORKDIR /app

# Build a hand-crafted x86-64 ELF64 executable with two PT_LOAD segments:
#   seg1: RX, file window [0, 0x210)  -> vaddr 0x400000
#   seg2: RW, file window [0x210, 0x214) -> vaddr 0x601000
# Sections: NULL, .text (in seg1), .rodata (in seg1), .data (in seg2),
# .shstrtab. All fields are internally consistent so that parsing + the
# standard load formula yields deterministic answers.
RUN python3 - <<'PYEOF'
import struct

def ehdr(e_entry, e_phoff, e_shoff, e_phnum, e_shnum, e_shstrndx):
    ident = b'\x7fELF' + bytes([2, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0])
    return struct.pack('<16sHHIQQQIHHHHHH', ident, 2, 62, 1, e_entry,
                       e_phoff, e_shoff, 0, 64, 56, e_phnum, 64, e_shnum,
                       e_shstrndx)

def phdr(p_type, p_flags, p_offset, p_vaddr, p_filesz, p_memsz, p_align):
    return struct.pack('<IIQQQQQQ', p_type, p_flags, p_offset, p_vaddr,
                       p_vaddr, p_filesz, p_memsz, p_align)

def shdr(sh_name, sh_type, sh_flags, sh_addr, sh_offset, sh_size,
         sh_link, sh_info, sh_addralign, sh_entsize):
    return struct.pack('<IIQQQQIIQQ', sh_name, sh_type, sh_flags, sh_addr,
                       sh_offset, sh_size, sh_link, sh_info,
                       sh_addralign, sh_entsize)

SHOFF   = 0xC0
TEXT    = 0x200
RODATA  = 0x204
DATA    = 0x210
SHSTRTAB = 0x214
RODATA_LEN = 12
DATA_LEN   = 4
SHSTR = b'\x00.text\x00.rodata\x00.data\x00.shstrtab\x00'

blob = bytearray()
blob += ehdr(0x400200, 0x40, SHOFF, 2, 5, 4)
# segment 1: RX, file [0, 0x210) at vaddr 0x400000
blob += phdr(1, 5, 0, 0x400000, DATA, DATA, 0x1000)
# segment 2: RW, file [0x210, 0x214) at vaddr 0x601000
blob += phdr(1, 6, DATA, 0x601000, DATA_LEN, DATA_LEN, 0x1000)
blob += b'\x00' * (SHOFF - len(blob))
# section header table (5 entries)
blob += shdr(0, 0, 0, 0, 0, 0, 0, 0, 0, 0)                                   # NULL
blob += shdr(1, 1, 6, 0x400200, TEXT, 4, 0, 0, 16, 0)                        # .text
blob += shdr(7, 1, 2, 0x400204, RODATA, RODATA_LEN, 0, 0, 1, 0)              # .rodata
blob += shdr(15, 1, 3, 0x601000, DATA, DATA_LEN, 0, 0, 8, 0)                 # .data
blob += shdr(21, 3, 0, 0, SHSTRTAB, len(SHSTR), 0, 0, 1, 0)                  # .shstrtab
assert len(blob) == TEXT, hex(len(blob))
blob += bytes([0x48, 0x31, 0xc0, 0xc3])      # .text : xor eax,eax ; ret
blob += b'hello world\x00'                   # .rodata
blob += bytes([0x2a, 0x00, 0x00, 0x00])      # .data : 4 bytes
blob += SHSTR
open('/app/prog', 'wb').write(bytes(blob))
print('wrote', len(blob), 'bytes')
PYEOF