#!/bin/bash
# Oracle: parse the ELF header + section table of /app/prog and report
# entry point, e_shoff/e_shnum and the .text section's sh_offset/sh_size.
set -euo pipefail
python3 - <<'PYEOF'
import struct

f = open('/app/prog', 'rb').read()
endian = '<' if f[5] == 1 else '>'
(e_type, e_machine, e_version, e_entry, e_phoff, e_shoff, e_flags,
 e_ehsize, e_phentsize, e_phnum, e_shentsize, e_shnum, e_shstrndx) = \
    struct.unpack_from(endian + 'HHIQQQIHHHHHH', f, 16)

# locate .shstrtab via e_shstrndx
sname, stype, sflags, saddr, soff, ssize, slink, sinfo, salign, sentsz = \
    struct.unpack_from(endian + 'IIQQQQIIQQ', f, e_shoff + e_shstrndx * e_shentsize)
shstr = f[soff:soff + ssize]

def find_section(name):
    pos = shstr.find(name.encode() + b'\x00')
    assert pos >= 0, name
    for i in range(e_shnum):
        n, t, fl, a, o, s, l, inf, al, es = struct.unpack_from(
            endian + 'IIQQQQIIQQ', f, e_shoff + i * e_shentsize)
        if n == pos:
            return o, s
    raise KeyError(name)

text_off, text_size = find_section('.text')
answers = {
    'entry_point': hex(e_entry),
    'shoff': hex(e_shoff),
    'shnum': hex(e_shnum),
    'text_sh_offset': hex(text_off),
    'text_sh_size': hex(text_size),
}
with open('/app/answer.txt', 'w') as out:
    for k in ('entry_point', 'shoff', 'shnum', 'text_sh_offset', 'text_sh_size'):
        out.write('%s=%s\n' % (k, answers[k]))
PYEOF
