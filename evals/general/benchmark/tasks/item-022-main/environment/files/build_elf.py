#!/usr/bin/env python3
"""Build a small but structurally valid little-endian ELF64 file.

This produces the master test asset for item-022-main. The resulting binary
is self-consistent: every table offset encoded in the ELF header points at the
matching structure in the payload.  Nothing about the file is revealed to the
agent beyond the file itself (this builder is deleted from the image after
Docker build time).
 """
import struct
import sys


def build(path):
    # ---- string table -------------------------------------------------------
    names = ['.shstrtab', '.text', '.data', '.rodata']
    strtab = b'\x00'
    name_off = {}
    for n in names:
        name_off[n] = len(strtab)
        strtab += n.encode('ascii') + b'\x00'

    # ---- section definitions: name -> (section_type, vaddr, size) -----------
    sec = [
        ('text',    2, 0x400000, 0x80),
        ('data',    1, 0x402000, 0x20),
        ('rodata',  2, 0x403000, 0x10),
    ]
    # ---- layout: bytes of header + phdr table + shdr table -------------------
    ehdr_size = 64
    phent_size = 56
    phnum = 1
    shent_size = 64
    shnum = 4
    phoff = ehdr_size
    shoff = phoff + phnum * phent_size
    body_start = shoff + shnum * shent_size

    # assign file offsets to sections sequentially
    off = body_start
    sections = []
    for name, stype, va, size in sec:
        sections.append((name, stype, va, off, size))
        off += size
    strtab_off = off
    strtab_va = 0x404000

    entry_va = 0x400000

    # ---- ELF header ---------------------------------------------------------
    ident = b'\x7fELF' + bytes([2, 1, 1, 0]) + bytes(8)
    ehdr = struct.pack(
        '<16sHHIQQQIHHHHHH',
        ident, 3, 62, 1, entry_va, phoff, shoff, 0,
        ehdr_size, phent_size, phnum, shent_size, shnum, 3,
    )

    # ---- program header (single PT_LOAD covering the data region) ----------
    phdr = struct.pack(
        '<IIQQQQQQ',
        1, 7, body_start, 0x400000, 0x400000, 0xB0, 0xB0, 0x1000,
    )

    # ---- section header table ----------------------------------------------
    shdrs = b''
    table = {
        '.text':    (2, 0x400000),
        '.data':    (1, 0x402000),
        '.rodata':  (2, 0x403000),
        '.shstrtab': (3, 0x404000),
    }
    order = ['.text', '.data', '.rodata', '.shstrtab']
    for nm in order:
        stype, addr = table[nm]
        if nm == '.shstrtab':
            soff, ssize = strtab_off, len(strtab)
        else:
            key = nm[1:]  # 'text' etc
            soff = next(s[3] for s in sections if s[0] == key)
            ssize = next(s[4] for s in sections if s[0] == key)
        shdrs += struct.pack(
            '<IIQQQQIIQQ',
            name_off[nm], stype, 0, addr, soff, ssize, 0, 0, 0x40, 0,
        )

    # ---- payload blobs -------------------------------------------------------
    text_blob = bytes((i * 7 + 3) & 0xFF for i in range(0x80))
    data_blob = bytes([0xA5] * 0x20)
    rodata_blob = bytes([0x5A, 0x5B, 0x5C, 0x5D] * 0x04)

    out = ehdr + phdr + shdrs + text_blob + data_blob + rodata_blob + strtab
    expected = strtab_off + len(strtab)
    assert len(out) == expected, (len(out), expected)
    with open(path, 'wb') as f:
        f.write(out)
    print('wrote %s (%d bytes)' % (path, len(out)))


if __name__ == '__main__':
    build(sys.argv[1])