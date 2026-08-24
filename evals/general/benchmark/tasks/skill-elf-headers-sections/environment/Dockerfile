FROM bench-base:python-3.12

WORKDIR /app

# Build a small hand-crafted x86-64 ELF64 executable (ET_EXEC) with a real
# ELF header, one PT_LOAD program header, and a section header table with
# 3 entries (.text, .shstrtab). All offsets/fields below are internally
# consistent, so parsing them reveals the expected answers.
RUN python3 - <<'PYEOF'
import struct

def ehdr(e_entry, e_phoff, e_shoff, e_phnum, e_shnum, e_shstrndx):
    ident = b'\x7fELF' + bytes([2, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0])  # ELF64, LE
    return struct.pack(
        '<16sHHIQQQIHHHHHH',
        ident, 2, 62, 1, e_entry, e_phoff, e_shoff, 0,
        64, 56, e_phnum, 64, e_shnum, e_shstrndx,
    )

def phdr(p_type, p_flags, p_offset, p_vaddr, p_filesz, p_memsz, p_align):
    return struct.pack('<IIQQQQQQ', p_type, p_flags, p_offset, p_vaddr,
                       p_vaddr, p_filesz, p_memsz, p_align)

def shdr(sh_name, sh_type, sh_flags, sh_addr, sh_offset, sh_size,
         sh_link, sh_info, sh_addralign, sh_entsize):
    return struct.pack('<IIQQQQIIQQ', sh_name, sh_type, sh_flags, sh_addr,
                       sh_offset, sh_size, sh_link, sh_info,
                       sh_addralign, sh_entsize)

TEXT_OFF   = 0x140
SHSTR_OFF  = 0x144
SHSTR      = b'\x00.text\x00.shstrtab\x00'      # .text name offset 1, .shstrtab 7
TEXT_CODE  = bytes([0x48, 0x31, 0xc0, 0xc3])    # xor eax,eax ; ret

blob = bytearray()
blob += ehdr(0x401000, 64, 128, 1, 3, 2)
blob += phdr(1, 5, 0, 0x400000, TEXT_OFF + len(TEXT_CODE), TEXT_OFF + len(TEXT_CODE), 0x1000)
blob += b'\x00' * (128 - len(blob))
# section header table: NULL, .text, .shstrtab
blob += shdr(0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
blob += shdr(1, 1, 6, 0x401000, TEXT_OFF, len(TEXT_CODE), 0, 0, 16, 0)
blob += shdr(7, 3, 0, 0, SHSTR_OFF, len(SHSTR), 0, 0, 1, 0)
assert len(blob) == 0x140, hex(len(blob))
blob += TEXT_CODE
blob += SHSTR
open('/app/prog', 'wb').write(bytes(blob))
print('wrote', len(blob), 'bytes')
PYEOF
