#!/bin/bash
# Real oracle for teal-assembler. Writes the /app/assemble.py deliverable
# (a genuine two-pass TAL-3 assembler), then RUNS it on /app/program.src
# to produce /app/program.bin. Does not read /tests and never cats a
# precomputed answer.
set -eu

cat > /app/assemble.py <<'PY'
#!/usr/bin/env python3
"""TAL-3 assembler.

Usage: python3 assemble.py <source.src> <output.bin>

Two-pass assembler for the TAL-3 instruction set described in /app/ISA.txt.
Pass 1 records label addresses and validated instructions; pass 2 encodes
bytes. Any error aborts with a nonzero exit status and a line-numbered
diagnostic on stderr, without writing the output file.
"""
import re
import sys

# mnemonic -> (byte length, number of operands)
LENGTHS = {'nop': 1, 'load': 3, 'add': 2, 'jmp': 3, 'halt': 1}
NARGS = {'nop': 0, 'load': 2, 'add': 2, 'jmp': 1, 'halt': 0}


def fail(line, msg):
    sys.stderr.write('line %d: %s\n' % (line, msg))
    sys.exit(1)


def tokenize(line):
    return [t for t in re.split(r'[,\s]+', line) if t]


def parse_reg(line, tok):
    m = re.fullmatch(r'[rR](\d{1,3})', tok)
    if not m:
        fail(line, "invalid register operand '%s'" % tok)
    v = int(m.group(1))
    if v > 15:
        fail(line, "register r%d out of range r0..r15" % v)
    return v


def parse_imm(line, tok):
    t = tok.lower()
    try:
        v = int(t, 16) if t.startswith('0x') else int(t, 10)
    except ValueError:
        fail(line, "invalid immediate '%s'" % tok)
    if not (0 <= v <= 255):
        fail(line, "immediate %d out of range 0..255" % v)
    return v


def main():
    if len(sys.argv) != 3:
        sys.stderr.write("usage: assemble.py <source.src> <output.bin>\n")
        sys.exit(2)
    src, out = sys.argv[1], sys.argv[2]
    try:
        raw = open(src, encoding='utf-8').read()
    except OSError as e:
        sys.stderr.write("cannot read %s: %s\n" % (src, e))
        sys.exit(2)

    lines = []           # (line_no, tokens)
    for num, text in enumerate(raw.splitlines(), 1):
        s = text.split('#', 1)[0].strip()
        if not s:
            continue
        lines.append((num, tokenize(s)))

    # ---- pass 1: labels and instruction records ----
    labels = {}
    instrs = []          # (line_no, mnemonic, operands)
    addr = 0
    for num, toks in lines:
        j = 0
        while j < len(toks) and toks[j].endswith(':'):
            name = toks[j][:-1]
            if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', name):
                fail(num, "invalid label '%s'" % toks[j])
            if name in labels:
                fail(num, "duplicate label '%s'" % name)
            labels[name] = addr
            j += 1
        if j >= len(toks):
            continue
        mnem = toks[j].lower()
        args = toks[j + 1:]
        if mnem not in LENGTHS:
            fail(num, "unknown mnemonic '%s'" % toks[j])
        if len(args) != NARGS[mnem]:
            fail(num, "%s: expected %d operand(s), got %d"
                 % (mnem, NARGS[mnem], len(args)))
        instrs.append((num, mnem, args))
        addr += LENGTHS[mnem]

    # ---- pass 2: encode ----
    buf = bytearray()
    for num, mnem, args in instrs:
        if mnem == 'nop':
            buf.append(0x00)
        elif mnem == 'load':
            r = parse_reg(num, args[0])
            im = parse_imm(num, args[1])
            buf += bytes((0x10, r, im))
        elif mnem == 'add':
            r1 = parse_reg(num, args[0])
            r2 = parse_reg(num, args[1])
            buf.append(0x20)
            buf.append((r1 << 4) | r2)
        elif mnem == 'jmp':
            tgt = args[0]
            if tgt not in labels:
                fail(num, "jump target '%s' is not a defined label" % tgt)
            a = labels[tgt]
            if not (0 <= a <= 65535):
                fail(num, "jump address %d out of 16-bit range" % a)
            buf += bytes((0x30, (a >> 8) & 0xFF, a & 0xFF))
        elif mnem == 'halt':
            buf.append(0xFF)

    with open(out, 'wb') as f:
        f.write(buf)


if __name__ == '__main__':
    main()
PY

python3 /app/assemble.py /app/program.src /app/program.bin
chmod +x /app/assemble.py