#!/usr/bin/env python3
"""classify.py - identify the architecture / container format of a blob by
inspecting its headers WITHOUT executing it (hollow-dial lab).

Usage:  python3 classify.py <file>
Writes a single JSON object to stdout:
    {"file","format","arch","host_executable","note"}

Detection rules (documented in instruction.md):
 * file starting with the ELF magic 0x7f 'E' 'L' 'F' -> inspect e_machine and
   report the architecture; host_executable is true only for x86_64 (this host).
 * a legacy PDP-11 a.out header (magic 0x0107 / 0x0108 / 0x010B / 0x00CC) ->
   arch "pdp11", host_executable false, format "a.out".
 * an MZ stub -> Windows PE stub.
 * otherwise -> "unknown" (plain text / truncated / garbage), exit 0.
A file that starts with the ELF magic but is too short for a header is reported
as format "elf-truncated" rather than crashing.
"""
import json
import struct
import sys

MACHINES = {
    3: 'x86', 5: 'm68k', 8: 'mips', 15: 'parisc', 18: 'sparc', 20: 'powerpc',
    21: 'powerpc64', 40: 'arm', 46: 'sh', 50: 'ia64', 62: 'x86_64',
    183: 'aarch64', 243: 'riscv',
}
PDP11_MAGICS = {0x0107, 0x0108, 0x010B, 0x00CC}


def classify(path):
    with open(path, 'rb') as f:
        d = f.read(96)
    out = {'file': path, 'format': 'unknown', 'arch': 'unknown',
           'host_executable': False, 'note': 'no recognizable executable header'}

    if d[:4] == b'\x7fELF':
        if len(d) < 20:
            out['format'] = 'elf-truncated'
            out['note'] = 'starts with ELF magic but the header is truncated'
            return out
        cls = d[4]
        enc = d[5]
        machine = struct.unpack_from('<H' if enc == 1 else '>H', d, 18)[0]
        out['format'] = 'elf-32' if cls == 1 else ('elf-64' if cls == 2 else 'elf')
        out['arch'] = MACHINES.get(machine, 'unknown-elf-machine-%d' % machine)
        out['host_executable'] = (machine == 62)
        out['note'] = ('native host executable (x86-64/amd64)'
                       if machine == 62 else
                       'non-host ELF for a foreign or embedded architecture')
        return out

    if len(d) >= 2 and struct.unpack_from('<H', d, 0)[0] in PDP11_MAGICS:
        out['format'] = 'a.out'
        out['arch'] = 'pdp11'
        out['note'] = ('legacy PDP-11 a.out image; machine code for an old '
                       '16-bit architecture, not runnable on this host')
        return out

    if d[:2] == b'MZ':
        out['format'] = 'pe'
        out['arch'] = 'x86-family'
        out['note'] = 'MS-DOS/Windows PE stub'
        return out

    if len(d) >= 8:
        text = sum(1 for b in d if b in (9, 10, 13) or 32 <= b < 127)
        if text / len(d) > 0.9:
            out['format'] = 'text'
            out['note'] = 'mostly printable text, not a machine-code image'
    return out


def main():
    if len(sys.argv) != 2:
        sys.stderr.write('usage: classify.py <file>\n')
        return 2
    sys.stdout.write(json.dumps(classify(sys.argv[1])) + '\n')
    return 0


if __name__ == '__main__':
    sys.exit(main())
