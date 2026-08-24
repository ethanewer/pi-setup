#!/usr/bin/env python3
"""Build a small but structured BIG-ENDIAN ELF64 file with a NOBITS
(SHT_NOBITS) section whose virtual range overlaps the entry point, and a
section header table that is NOT sorted by address.

Produces the master test asset for item-022-hard.  The builder is removed
from the image after Docker build; the file itself must be inspectable.
 """
import struct
import sys


def build(path):
    E = '>'

    # ---- string table -------------------------------------------------------
    names = ['.shstrtab', '.nobits', '.text', '.data', '.rodata']
    strtab = b'\x00'
    name_off = {}
    for n in names:
        name_off[n] = len(strtab)
        strtab += n.encode('ascii') + b'\x00'

    ehdr_size = 64
    phent_size = 56
    phnum = 1
    shent_size = 64
    shnum = 5
    phoff = ehdr_size
    shoff = phoff + phnum * phent_size
    body_start = shoff + shnum * shent_size

    # payload sizes (bytes) for the file-backed sections
    text_len = 0x100
    data_len = 0x40
    rodata_len = 0x20
    text_va = 0x400000
    total_size = body_start + text_len + data_len + rodata_len + len(strtab)

    # NOBITS section carries no file bytes; its file offset is made to be
    # beyond the end of the file on purpose.
    nobits_off = total_size
    nobits_va = 0x600040
    entry_va = 0x600050

    # sections: name -> (sh_type, virtual address, file offset, size)
    sec_desc = {
        '.text':    (2, 0x600000, body_start,           text_len),
        '.data':    (1, 0x650000, body_start + text_len, data_len),
        '.rodata':  (2, 0x660000, body_start + text_len + data_len, rodata_len),
        '.shstrtab': (3, 0x700000, body_start + text_len + data_len + rodata_len,
                      len(strtab)),
        '.nobits':  (8, 0x600040, nobits_off, 0x40),
    }

    ident = b'\x7fELF' + bytes([2, 2, 1, 0]) + bytes(8)  # EI_DATA=2 -> big-endian
    ehdr = struct.pack(
        '>16sHHIQQQIHHHHHH',
        ident, 3, 0x3E, 1, entry_va, phoff, shoff, 0,
        ehdr_size, phent_size, phnum, shent_size, shnum, 0,
    )

    # program header: a single loaded region over the three data sections
    phdr = struct.pack(
        '>IIQQQQQQ',
        1, 7, body_start, 0x400000, 0x400000,
        text_len + data_len + rodata_len,
        text_len + data_len + rodata_len,
        0x1000,
    )

    # Section table order (NOT address/sorted, to force a table-order scan)
    order = ['.shstrtab', '.nobits', '.text', '.data', '.rodata']
    shdrs = b''
    for nm in order:
        st, addr, off, size = sec_desc[nm]
        shdrs += struct.pack(
            '>IIQQQQIIQQ',
            name_off[nm], st, 0, addr, off, size, 0, 0, 0x40, 0,
        )

    text_blob = bytes((i * 3 + 11) & 0xFF for i in range(text_len))
    data_blob = bytes([0xA5] * data_len)
    rodata_blob = bytes([0x5A, 0x6A, 0x7C, 0x4D] * (rodata_len // 4))

    out = ehdr + phdr + shdrs + text_blob + data_blob + rodata_blob + strtab
    assert len(out) == total_size, (len(out), total_size)
    with open(path, 'wb') as f:
        f.write(out)
    print('wrote %s (%d bytes)' % (path, len(out)))
    print('expected entry_file_offset =', hex(body_start + entry_va - 0x600000))


if __name__ == '__main__':
    build(sys.argv[1])