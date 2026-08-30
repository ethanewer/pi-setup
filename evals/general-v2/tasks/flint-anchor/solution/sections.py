#!/usr/bin/env python3
"""flint section & symbol-string resolver.

Parses an ELF file and reports:
  * every section header:  "<idx> <name> <vaddr> <size>"  (decimal)
  * every .symtab symbol whose type is FUNC or OBJECT and which has a
    non-empty name resolved through its linked string table:
        "<value> <name>"   (decimal value, natural symtab order)

Usage:  python3 sections.py <elf-file>
"""
import struct
import sys

ELF64_EHDR = "<16sHHIQQQIHHHHHH"
ELF64_SHDR = "<IIQQQQIIQQ"
ELF64_SYM = "<IBBHQQ"

SHT_SYMTAB = 2
STT_OBJECT = 1
STT_FUNC = 2


def cstr(elf, off):
    elf.seek(off)
    out = bytearray()
    while True:
        b = elf.read(1)
        if not b or b == b"\x00":
            return out.decode("utf-8", "replace")
        out += b


def main():
    if len(sys.argv) < 2:
        sys.stderr.write("usage: sections.py <elf-file>\n")
        return 1
    with open(sys.argv[1], "rb") as elf:
        eh = struct.unpack(ELF64_EHDR, elf.read(64))
        e_shoff, e_shentsize, e_shnum, e_shstrndx = eh[6], eh[11], eh[12], eh[13]

        shdrs = []
        elf.seek(e_shoff)
        for _ in range(e_shnum):
            shdrs.append(struct.unpack(ELF64_SHDR, elf.read(e_shentsize)))

        shstr_off = shdrs[e_shstrndx][4]      # section-name string table
        names = [cstr(elf, shstr_off + sh[0]) for sh in shdrs]

        lines = []
        lines.append("SECTIONS %d" % e_shnum)
        for i, sh in enumerate(shdrs):
            lines.append("%d %s %d %d" % (i, names[i], sh[3], sh[5]))

        # symbol table (and its linked string table, sh_link) if present
        symtab = next((s for s in shdrs if s[1] == SHT_SYMTAB), None)
        if symtab is None:
            lines.append("SYMBOLS 0")
        else:
            entsize = symtab[9] or 24
            n_syms = symtab[5] // entsize
            strtab_off = shdrs[symtab[6]][4]
            syms = []
            for k in range(n_syms):
                elf.seek(symtab[4] + k * entsize)
                st_name, st_info, _, _, st_value, _ = struct.unpack(ELF64_SYM, elf.read(24))
                if (st_info & 0x0f) in (STT_OBJECT, STT_FUNC) and st_name:
                    nm = cstr(elf, strtab_off + st_name)
                    if nm:
                        syms.append((st_value, nm))
            lines.append("SYMBOLS %d" % len(syms))
            for value, nm in syms:
                lines.append("%d %s" % (value, nm))

        sys.stdout.write("\n".join(lines) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
