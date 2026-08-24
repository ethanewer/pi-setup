#!/bin/bash
# Oracle: compute ELF load addresses from program headers + section table
# of /app/prog using the standard PT_LOAD mapping rule.
set -euo pipefail
python3 - <<'PYEOF'
import struct

f = open('/app/prog', 'rb').read()
endian = '<' if f[5] == 1 else '>'
(e_type, e_machine, e_version, e_entry, e_phoff, e_shoff, e_flags,
 e_ehsize, e_phentsize, e_phnum, e_shentsize, e_shnum, e_shstrndx) = \
    struct.unpack_from(endian + 'HHIQQQIHHHHHH', f, 16)

loads = []
for i in range(e_phnum):
    pt, pfl, po, pv, pp, pfs, pms, pal = struct.unpack_from(
        endian + 'IIQQQQQQ', f, e_phoff + i * e_phentsize)
    if pt == 1:  # PT_LOAD
        loads.append((pfl, po, pv, pfs, pms))

# section name -> (sh_flags, sh_offset, sh_size)
def section(name):
    sn, st, sfl, sa, so, ss, sl, si, sal, ses = struct.unpack_from(
        endian + 'IIQQQQIIQQ', f, e_shoff + e_shstrndx * e_shentsize)
    shstr = f[so:so + ss]
    pos = shstr.find(name.encode() + b'\x00')
    for i in range(e_shnum):
        n, t, fl, a, o, s, l, inf, al, es = struct.unpack_from(
            endian + 'IIQQQQIIQQ', f, e_shoff + i * e_shentsize)
        if n == pos:
            return fl, o, s
    raise KeyError(name)

def va_of(name):
    fl, o, s = section(name)
    for pfl, po, pv, pfs, pms in loads:
        if po <= o < po + pfs:
            return pv + (o - po)
    raise KeyError('no segment covers ' + name)

# first writable PT_LOAD segment and its end address
data_seg_end = None
for pfl, po, pv, pfs, pms in loads:
    if pfl & 2:
        data_seg_end = pv + pms
        break
assert data_seg_end is not None

answers = {
    'nload': hex(len(loads)),
    'text_vaddr': hex(va_of('.text')),
    'data_vaddr': hex(va_of('.data')),
    'data_seg_end': hex(data_seg_end),
}
with open('/app/answer.txt', 'w') as out:
    for k in ('nload', 'text_vaddr', 'data_vaddr', 'data_seg_end'):
        out.write('%s=%s\n' % (k, answers[k]))
PYEOF