#!/usr/bin/env python3
"""Tiny assembler for the MIPS32 subset used by the item-042 tasks.

Output: a flat big-endian ELF32 with one PT_LOAD segment at 0x100000
(executable+writable, aligned 0x1000). Entry = 0x100000.

Usage: asm.py src.s -o out.elf

Syntax: one instruction or directive per line, '#' comments, '.set NAME,VAL'.
Registers: $zero $at $v0 $v1 $a0..$a3 $t0..$t9 $s0..$s7 $k0 $k1 $gp $sp $fp
$ra or $0..$31.

Pseudo ops: nop li la move.  Data: .word .asciiz .space .set.
Branches/jumps take labels (or '0' for a placeholder; patched by the linker
is out of scope — labels only).  Forward references OK (two passes).
"""
import sys
import struct
import re

BASE = 0x100000
EH_SIZE = 52
PH_SIZE = 32
PH_OFF = 52
DATA_OFF = PH_OFF + PH_SIZE

REG = {
    'zero': 0, 'at': 1, 'v0': 2, 'v1': 3, 'a0': 4, 'a1': 5, 'a2': 6, 'a3': 7,
    't0': 8, 't1': 9, 't2': 10, 't3': 11, 't4': 12, 't5': 13, 't6': 14,
    't7': 15, 's0': 16, 's1': 17, 's2': 18, 's3': 19, 's4': 20, 's5': 21,
    's6': 22, 's7': 23, 't8': 24, 't9': 25, 'k0': 26, 'k1': 27, 'gp': 28,
    'sp': 29, 'fp': 30, 'ra': 31,
}
for i in range(32):
    REG[str(i)] = i


def reg(tok):
    tok = tok.rstrip(',')
    if not tok.startswith('$'):
        raise ValueError('expected register, got %r' % tok)
    name = tok[1:]
    if name not in REG:
        raise ValueError('unknown register %r' % tok)
    return REG[name]


def imm(tok, signed=False):
    tok = tok.rstrip(',')
    m = re.match(r'^([-+]?)(0[xX][0-9a-fA-F]+|\d+)$', tok.strip())
    if m:
        sign = -1 if m.group(1) == '-' else 1
        v = int(m.group(2), 16 if m.group(2)[:2].lower() == '0x' else 10)
        return sign * v
    raise ValueError('expected immediate, got %r' % tok)


def w_rtype(rs, rt, rd, shamt, funct):
    return (0 << 26) | (rs << 21) | (rt << 16) | (rd << 11) | (shamt << 6) | funct


def w_itype(op, rs, rt, im):
    return (op << 26) | (rs << 21) | (rt << 16) | (im & 0xFFFF)


def w_jtype(op, target26):
    return (op << 26) | (target26 & 0x03FFFFFF)


BE = '>I'


class Asm:
    def __init__(self, lines):
        self.lines = lines
        self.consts = {}
        self.labels = {}
        self.size = 0
        self.entries = []     # list of (offset, word-or-bytes, ...)

    def parse_line(self, line):
        line = line.split('#', 1)[0].strip()
        if not line:
            return None, []
        toks = []
        while line:
            m = re.match(r'^\s+', line)
            if m:
                line = line[m.end():]
                continue
            if line[0] == '"':
                end = line.find('"', 1)
                assert end != -1
                toks.append(line[:end + 1])
                line = line[end + 1:]
                continue
            m = re.match(r'^[^\s]+', line)
            toks.append(m.group(0))
            line = line[m.end():]
        # split off an optional leading label
        label = None
        if toks and toks[0].endswith(':'):
            label = toks[0][:-1]
            toks = toks[1:]
        return label, toks

    def size_line(self, toks, addr):
        """Return byte size of the line's payload (pass 1)."""
        if not toks:
            return 0
        op = toks[0].lower()
        if op.startswith('.'):
            if op == '.set':
                return 0
            if op == '.word':
                for t in toks[1:]:
                    pass
                return 4 * (len(toks) - 1)
            if op == '.asciiz':
                s = toks[1]
                return self._str_len(s) + 1
            if op == '.space':
                return imm(toks[1])
            raise ValueError('unknown directive ' + op)
        if op in ('nop', 'syscall', 'mthi', 'mtlo'):
            return 4
        if op in ('jr', 'jalr'):
            return 4
        if op in ('bltz', 'bgez', 'bltzal', 'bgezal', 'blez', 'bgtz', 'j', 'jal'):
            return 4
        if op in ('div', 'divu', 'mult', 'multu'):
            return 4
        if op in ('add', 'addu', 'sub', 'subu', 'and', 'or', 'xor', 'nor',
                  'slt', 'sltu', 'sllv', 'srlv', 'srav'):
            return 4
        if op in ('sll', 'srl', 'sra'):
            return 4
        if op in ('mfhi', 'mflo'):
            return 4
        if op in ('addi', 'addiu', 'slti', 'sltiu', 'andi', 'ori', 'xori', 'lui'):
            return 4
        if op in ('beq', 'bne'):
            return 4
        if op in ('lb', 'lh', 'lwl', 'lw', 'lbu', 'lhu', 'lwr', 'sb', 'sh', 'swl', 'sw'):
            return 4
        if op == 'li':
            return 8 if not self._li_small(toks[1:]) else 4
        if op == 'la':
            return 8 if (BASE + addr < 65536 or True) else 4
        if op == 'move':
            return 4
        raise ValueError('unknown instruction ' + op)

    def _str_len(self, s):
        return len(self._parse_str(s))

    def _parse_str(self, s):
        body = s[1:-1]
        out = []
        i = 0
        while i < len(body):
            c = body[i]
            if c == '\\' and i + 1 < len(body):
                n = body[i + 1]
                out.append({'n': 10, 't': 9, '\\': 92, '"': 34, '0': 0}.get(n, ord(n)))
                i += 2
            else:
                out.append(ord(c))
                i += 1
        return bytes(out)

    def _li_small(self, toks):
        v = imm(toks[1])
        return -32768 <= v <= 65535

    def pass1(self):
        addr = 0
        for raw in self.lines:
            label, toks = self.parse_line(raw)
            if label:
                self.labels[label] = BASE + addr
            if toks and toks[0].lower() == '.set':
                self.consts[self._name(toks[1])] = imm(toks[2])
            sz = self.size_line(toks, addr) if toks else 0
            addr += sz
        self.size = addr

    def _name(self, tok):
        return tok.rstrip(',')

    def pass2(self):
        out = bytearray()
        addr = 0
        for raw in self.lines:
            label, toks = self.parse_line(raw)
            if toks and toks[0].lower() == '.set':
                continue
            if not toks:
                continue
            op = toks[0].lower()
            here = BASE + addr
            if op.startswith('.'):
                if op == '.word':
                    vals = [self.res(t) for t in toks[1:]]
                    out += b''.join(struct.pack(BE, v & 0xFFFFFFFF) for v in vals)
                elif op == '.asciiz':
                    out += self._parse_str(toks[1]) + b'\x00'
                elif op == '.space':
                    out += b'\x00' * imm(toks[1])
                addr = len(out)
                continue
            w = self.enc(op, toks, here)
            if isinstance(w, int):
                w = [w]
            for word in w:
                out += struct.pack(BE, word)
            addr = len(out)
        return bytes(out)

    def res(self, tok):
        """resolve label or constant"""
        t = tok.rstrip(',')
        if t in self.labels:
            return self.labels[t]
        if t in self.consts:
            return self.consts[t]
        m = re.match(r'^([-+]?)(0[xX][0-9a-fA-F]+|\d+)$', t)
        if m:
            sign = -1 if m.group(1) == '-' else 1
            return sign * int(m.group(2), 16 if m.group(2)[:2].lower() == '0x' else 10)
        raise ValueError('cannot resolve %r' % t)

    def enc(self, op, toks, here):
        extra = toks[1:]
        if op == 'nop':
            return w_rtype(0, 0, 0, 0, 0)
        if op == 'syscall':
            return w_rtype(0, 0, 0, 0, 0x0c)
        if op == 'jr':
            return w_rtype(reg(extra[0]), 0, 0, 0, 0x08)
        if op == 'jalr':
            return w_rtype(reg(extra[0]), 0, 0, 0, 0x09)
        if op == 'mfhi':
            return w_rtype(0, 0, reg(extra[0]), 0, 0x10)
        if op == 'mflo':
            return w_rtype(0, 0, reg(extra[0]), 0, 0x12)
        if op == 'mthi':
            return w_rtype(reg(extra[0]), 0, 0, 0, 0x11)
        if op == 'mtlo':
            return w_rtype(reg(extra[0]), 0, 0, 0, 0x13)
        if op in ('add', 'addu', 'sub', 'subu', 'and', 'or', 'xor', 'nor', 'slt', 'sltu'):
            f = {'add': 0x20, 'addu': 0x21, 'sub': 0x22, 'subu': 0x23, 'and': 0x24,
                 'or': 0x25, 'xor': 0x26, 'nor': 0x27, 'slt': 0x2a, 'sltu': 0x2b}[op]
            rd, rs_, rt_ = reg(extra[0]), reg(extra[1]), reg(extra[2])
            return w_rtype(rs_, rt_, rd, 0, f)
        if op in ('sllv', 'srlv', 'srav'):
            f = {'sllv': 0x04, 'srlv': 0x06, 'srav': 0x07}[op]
            rd, rs_, rt_ = reg(extra[0]), reg(extra[1]), reg(extra[2])
            return w_rtype(rs_, rt_, rd, 0, f)
        if op in ('sll', 'srl', 'sra'):
            f = {'sll': 0x00, 'srl': 0x02, 'sra': 0x03}[op]
            rd, rt_, sh = reg(extra[0]), reg(extra[1]), imm(extra[2])
            return w_rtype(0, rt_, rd, sh & 31, f)
        if op in ('div', 'divu', 'mult', 'multu'):
            f = {'mult': 0x00, 'multu': 0x01, 'div': 0x02, 'divu': 0x03}[op]
            rs_, rt_ = reg(extra[0]), reg(extra[1])
            return (28 << 26) | (rs_ << 21) | (rt_ << 16) | f
        if op in ('addi', 'addiu', 'slti', 'sltiu', 'andi', 'ori', 'xori'):
            oc = {'addi': 8, 'addiu': 9, 'slti': 10, 'sltiu': 11, 'andi': 12, 'ori': 13, 'xori': 14}[op]
            v = self.res(extra[2])
            rt_, rs_ = reg(extra[0]), reg(extra[1])
            return w_itype(oc, rs_, rt_, v)
        if op == 'lui':
            rt_, v = reg(extra[0]), self.res(extra[1])
            return w_itype(15, 0, rt_, v)
        if op in ('beq', 'bne'):
            oc = 4 if op == 'beq' else 5
            rs_, rt_, tgt = reg(extra[0]), reg(extra[1]), self.res(extra[2])
            off = (tgt - (here + 4)) >> 2
            if not -0x8000 <= off <= 0x7FFF:
                raise ValueError('branch offset out of range')
            return w_itype(oc, rs_, rt_, off)
        if op in ('bltz', 'bgez', 'bltzal', 'bgezal'):
            oc = {'bltz': 0, 'bgez': 1, 'bltzal': 16, 'bgezal': 17}[op]
            rs_, tgt = reg(extra[0]), self.res(extra[1])
            off = (tgt - (here + 4)) >> 2
            if not -0x8000 <= off <= 0x7FFF:
                raise ValueError('branch offset out of range')
            return w_itype(1, rs_, oc, off & 0xFFFF)
        if op in ('blez', 'bgtz'):
            oc = 6 if op == 'blez' else 7
            rs_, tgt = reg(extra[0]), self.res(extra[1])
            off = (tgt - (here + 4)) >> 2
            if not -0x8000 <= off <= 0x7FFF:
                raise ValueError('branch offset out of range')
            return w_itype(oc, rs_, 0, off & 0xFFFF)
        if op in ('j', 'jal'):
            oc = 2 if op == 'j' else 3
            tgt = self.res(extra[0])
            return w_jtype(oc, tgt >> 2)
        if op == 'li':
            v = self.res(extra[1])
            rt_ = reg(extra[0])
            if -32768 <= v <= 32767:
                return w_itype(9, 0, rt_, v)
            if 0 <= v <= 65535:
                return w_itype(13, 0, rt_, v)
            u = v & 0xFFFFFFFF
            return [w_itype(15, 0, rt_, (u >> 16) & 0xFFFF),
                    w_itype(13, rt_, rt_, u & 0xFFFF)]
        if op == 'la':
            v = self.res(extra[1])
            rt_ = reg(extra[0])
            u = v & 0xFFFFFFFF
            if 0 <= u <= 0xFFFF:
                return w_itype(13, 0, rt_, u)
            return [w_itype(15, 0, rt_, (u >> 16) & 0xFFFF),
                    w_itype(13, rt_, rt_, u & 0xFFFF)]
        if op == 'move':
            rd, rs_ = reg(extra[0]), reg(extra[1])
            return w_rtype(rs_, 0, rd, 0, 0x21)  # addu rd, rs, $zero
        if op in ('lb', 'lh', 'lwl', 'lw', 'lbu', 'lhu', 'lwr', 'sb', 'sh', 'swl', 'sw'):
            oc = {'lb': 0x20, 'lh': 0x21, 'lwl': 0x22, 'lw': 0x23, 'lbu': 0x24,
                  'lhu': 0x25, 'lwr': 0x26, 'sb': 0x28, 'sh': 0x29, 'swl': 0x2a, 'sw': 0x2b}[op]
            rt_ = reg(extra[0])
            m = re.match(r'^(.*)\((.*)\)$', extra[1])
            offs = 0
            base_r = 0
            if m:
                offs = self.res(m.group(1))
                base_r = reg(m.group(2))
            else:
                # label/direct address
                addr = self.res(extra[1])
                offs = addr - BASE + DATA_OFF  # absolute from base not needed; keep addr
                offs = self.res(extra[1])
            return w_itype(oc, base_r, rt_, offs)
        raise ValueError('cannot encode ' + op)


def build(src, out_path):
    with open(src) as f:
        lines = f.read().split('\n')
    a = Asm(lines)
    a.pass1()
    code = a.pass2()
    total = DATA_OFF + len(code)
    out = bytearray()

    P = struct.pack
    out += b'\x7fELF' + bytes([1, 2, 1, 0, 0]) + bytes(7)
    out += P('>HH', 2, 8)           # e_type ET_EXEC, e_machine EM_MIPS
    out += P('>I', 1)               # e_version
    out += P('>I', BASE)            # e_entry
    out += P('>I', PH_OFF)          # e_phoff
    out += P('>I', 0)               # e_shoff
    out += P('>I', 0)               # e_flags
    out += P('>HHHHH', EH_SIZE, PH_SIZE, 1, 0, 0)  # ehsize,phentsize,phnum,shentsize,shnum
    out += P('>H', 0)               # e_shstrndx
    out += P('>I', 1)               # p_type PT_LOAD
    out += P('>I', 7)               # p_flags RWE
    out += P('>I', DATA_OFF)        # p_offset
    out += P('>I', BASE)            # p_vaddr
    out += P('>I', BASE)            # p_paddr
    out += P('>I', len(code))       # p_filesz
    out += P('>I', len(code))       # p_memsz
    out += P('>I', 0x1000)          # p_align
    out += code
    with open(out_path, 'wb') as f:
        f.write(bytes(out))
    return BASE + len(code) - 1


if __name__ == '__main__':
    src = sys.argv[1]
    out = sys.argv[3] if len(sys.argv) > 3 and sys.argv[2] == '-o' else 'a.elf'
    build(src, out)
    print('assembled %s -> %s' % (src, out))