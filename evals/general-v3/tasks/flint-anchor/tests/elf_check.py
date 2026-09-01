#!/usr/bin/env python3
"""flint ELF resolver verifier.

Computes the expected SECTIONS / SYMBOLS output for an ELF by an independent
parser implementing the documented rule, then compares the agent's sections.py
output line-by-line. Exits 0 iff they match exactly.
"""
import struct
import sys

ELF64_EHDR = "<16sHHIQQQIHHHHHH"
ELF64_SHDR = "<IIQQQQIIQQ"
ELF64_SYM = "<IBBHQQ"
SHT_SYMTAB = 2
STT_OBJECT = 1
STT_FUNC = 2


def expected(path):
    with open(path, "rb") as f:
        eh = struct.unpack(ELF64_EHDR, f.read(64))
        e_shoff, e_shentsize, e_shnum, e_shstrndx = eh[6], eh[11], eh[12], eh[13]
        f.seek(e_shoff)
        shdrs = [struct.unpack(ELF64_SHDR, f.read(e_shentsize)) for _ in range(e_shnum)]
        shstr_off = shdrs[e_shstrndx][4]

        def cstr(off):
            f.seek(off)
            b = bytearray()
            while True:
                ch = f.read(1)
                if not ch or ch == b"\x00":
                    return b.decode("utf-8", "replace")
                b += ch

        lines = ["SECTIONS %d" % e_shnum]
        for i, sh in enumerate(shdrs):
            lines.append("%d %s %d %d" % (i, cstr(shstr_off + sh[0]), sh[3], sh[5]))
        symtab = next((s for s in shdrs if s[1] == SHT_SYMTAB), None)
        if symtab is None:
            lines.append("SYMBOLS 0")
        else:
            entsize = symtab[9] or 24
            n_syms = symtab[5] // entsize
            strtab_off = shdrs[symtab[6]][4]
            syms = []
            for k in range(n_syms):
                f.seek(symtab[4] + k * entsize)
                st_name, st_info, _, _, st_value, _ = struct.unpack(ELF64_SYM, f.read(24))
                if (st_info & 0x0f) in (STT_OBJECT, STT_FUNC) and st_name:
                    nm = cstr(strtab_off + st_name)
                    if nm:
                        syms.append((st_value, nm))
            lines.append("SYMBOLS %d" % len(syms))
            for value, nm in syms:
                lines.append("%d %s" % (value, nm))
        return lines


def main():
    elf, got_path = sys.argv[1], sys.argv[2]
    with open(got_path) as f:
        got = [ln.rstrip("\n") for ln in f.read().splitlines()]
    want = expected(elf)
    if got == want:
        print("ELF-OK %s" % elf)
        return 0
    print("ELF-MISMATCH for %s" % elf)
    print("--- got ---")
    print("\n".join(got[:40]))
    print("--- want ---")
    print("\n".join(want[:40]))
    return 1


if __name__ == "__main__":
    sys.exit(main())
