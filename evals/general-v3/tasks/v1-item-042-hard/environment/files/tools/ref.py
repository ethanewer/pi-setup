#!/usr/bin/env python3
"""Reference MIPS32-subset emulator (big-endian ELF32, o32 syscalls).

Ground truth for the Harbor item-042 task. The agent writes a compatible
emulator in Node.js ("vm.js") and differential-tests it against this program,
which ships in the task image as /app/tools/ref.py.

Implemented subset (opcode:name):
  R-type (op=0):  sll00 srl02 sra03 sllv04 srlv06 srav07
                  jr08 jalr09 mfhi10 mthi11 mflo12 mtlo13 syscall0c
                  add20 addu21 sub22 subu23 and24 or25 xor26 nor27
                  slt2a sltu2b
  special2 (op=28): mult00 multu01 div02 divu03
  REGIMM (op=1): bltz00 bgez01 bltzal10 bgezal11   (in bits rt)
  branch: beq04 bne05 blez06 bgtz07
  imm:    addi08 addiu09 slti0a sltiu0b andi0c ori0d xori0e lui0f
  jump:   j02 jal03
  mem:    lb20 lh21 lwl22 lw23 lbu24 lhu25 lwr26 sb28 sh29 swl2a sw2b

Registers: 32 x u32; r0 hard-zero; r29=$sp; r30=$fp; r31=$ra.
Memory: 4 MiB. Code/data load at ELF PT_LOAD base, pc = ELF entry,
$sp = 0x200000 (STACK_BASE), all other regs 0. No branch delay slots.

Syscalls ($v0 = number, args $a0..$a2):
  4001 exit(code)     4004 write(fd, addr, count)   4003 read(fd, addr, count)

Modes:
  default      run; print guest stdout bytes as text; exit with guest exit code
  --trace      print one log line per instruction plus syscall/exit/trap lines
  --snapshot   print final JSON {"pc":..,"regs":[32]} instead of stdout
  --stdin FILE provide bytes for the read(0,...) syscall
"""
import sys
import struct
import json

MEM = 1 << 22          # 4 MiB
STACK_BASE = 0x200000
STEP_LIMIT = 1000000


def u32(x): return x & 0xFFFFFFFF


def s32(x):
    x &= 0xFFFFFFFF
    return x - 0x100000000 if x & 0x80000000 else x


def x16(v):
    v &= 0xFFFF
    return v - 0x10000 if v & 0x8000 else v


class VM:
    def __init__(self, stdin=b''):
        self.mem = bytearray(MEM)
        self.r = [0] * 32
        self.pc = 0
        self.base = 0
        self.hi = 0
        self.lo = 0
        self.stdin = stdin
        self.sinpos = 0
        self.stdout = bytearray()
        self.exited = False
        self.exitcode = 0
        self.log = []
        self._extra = []

    # ---- register helpers ----
    def g(self, i): return self.r[i]

    def s(self, i, v):
        if i != 0:
            self.r[i] = u32(v)

    # ---- memory ----
    def rd8(self, a):
        if not (0 <= a < MEM): raise RuntimeError('segv')
        return self.mem[a]

    def rd16(self, a):
        if not (0 <= a < MEM - 1): raise RuntimeError('segv')
        return (self.mem[a] << 8) | self.mem[a + 1]

    def rd32(self, a):
        if not (0 <= a < MEM - 3): raise RuntimeError('segv')
        return ((self.mem[a] << 24) | (self.mem[a + 1] << 16) |
                (self.mem[a + 2] << 8) | self.mem[a + 3])

    def wr8(self, a, v):
        if not (0 <= a < MEM): raise RuntimeError('segv')
        self.mem[a] = u32(v) & 0xFF

    def wr16(self, a, v):
        if not (0 <= a < MEM - 1): raise RuntimeError('segv')
        v &= 0xFFFF
        self.mem[a] = v >> 8
        self.mem[a + 1] = v & 0xFF

    def wr32(self, a, v):
        if not (0 <= a < MEM - 3): raise RuntimeError('segv')
        v &= 0xFFFFFFFF
        self.mem[a] = v >> 24
        self.mem[a + 1] = (v >> 16) & 0xFF
        self.mem[a + 2] = (v >> 8) & 0xFF
        self.mem[a + 3] = v & 0xFF

    def wrbytes(self, a, data):
        for i, b in enumerate(data):
            self.wr8(a + i, b)

    # ---- loader: flat ELF32 big-endian, one PT_LOAD ----
    def load_elf(self, path):
        d = open(path, 'rb').read()
        if d[:4] != b'\x7fELF':
            raise RuntimeError('not-elf')
        if d[4] != 1 or d[5] != 2:
            raise RuntimeError('not-elf32-be')
        self.pc = struct.unpack('>I', d[24:28])[0]
        phoff = struct.unpack('>I', d[28:32])[0]
        phentsize = struct.unpack('>H', d[42:44])[0]
        phnum = struct.unpack('>H', d[44:46])[0]
        for i in range(phnum):
            p = phoff + i * phentsize
            pt = struct.unpack('>I', d[p:p + 4])[0]
            if pt == 1:
                po = struct.unpack('>I', d[p + 8:p + 12])[0]
                pv = struct.unpack('>I', d[p + 12:p + 16])[0]
                pfs = struct.unpack('>I', d[p + 20:p + 24])[0]
                pms = struct.unpack('>I', d[p + 24:p + 28])[0]
                self.base = pv
                self.wrbytes(pv, d[po:po + pfs])
                if pms > pfs:
                    for j in range(pfs, pms):
                        self.wr8(pv + j, 0)

    # ---- instruction execution ----
    def run(self):
        self.s(29, STACK_BASE)          # $sp
        try:
            steps = 0
            while not self.exited:
                self.step()
                steps += 1
                if steps > STEP_LIMIT:
                    raise RuntimeError('step-limit')
        except RuntimeError as e:
            msg = str(e)
            if msg.startswith('illegal-opcode'):
                self.exitcode = 132
            elif msg == 'segv':
                self.exitcode = 139
            else:
                self.exitcode = 1
            self.log.append('vm trap: ' + msg)

    def step(self):
        self._extra = []
        curr = self.pc
        self.cur = curr
        w = self.rd32(curr)             # raises 'segv' if pc out of bounds
        op = (w >> 26) & 63
        rs = (w >> 21) & 31
        rt = (w >> 16) & 31
        rd = (w >> 11) & 31
        shamt = (w >> 6) & 31
        funct = w & 63
        imm16 = w & 0xFFFF
        simm16 = x16(imm16)
        nxt = u32(curr + 4)

        if op == 0:
            name, nxt = self.op_special(funct, rs, rt, rd, shamt, nxt)
        elif op == 1:
            name, nxt = self.op_regimm(rs, rt, simm16, nxt)
        elif op == 2:
            name = 'j'
            nxt = u32((nxt & 0xF0000000) | ((w & 0x03FFFFFF) << 2))
        elif op == 3:
            name = 'jal'
            self.s(31, nxt)
            nxt = u32((nxt & 0xF0000000) | ((w & 0x03FFFFFF) << 2))
        elif op == 4:
            name = 'beq'
            if self.g(rs) == self.g(rt):
                nxt = u32(nxt + (simm16 << 2))
        elif op == 5:
            name = 'bne'
            if self.g(rs) != self.g(rt):
                nxt = u32(nxt + (simm16 << 2))
        elif op == 6:
            name = 'blez'
            if s32(self.g(rs)) <= 0:
                nxt = u32(nxt + (simm16 << 2))
        elif op == 7:
            name = 'bgtz'
            if s32(self.g(rs)) > 0:
                nxt = u32(nxt + (simm16 << 2))
        elif op == 8:
            name = 'addi'; self.s(rt, s32(self.g(rs)) + simm16)
        elif op == 9:
            name = 'addiu'; self.s(rt, self.g(rs) + simm16)
        elif op == 10:
            name = 'slti'; self.s(rt, 1 if s32(self.g(rs)) < simm16 else 0)
        elif op == 11:
            name = 'sltiu'; self.s(rt, 1 if self.g(rs) < imm16 else 0)
        elif op == 12:
            name = 'andi'; self.s(rt, self.g(rs) & imm16)
        elif op == 13:
            name = 'ori'; self.s(rt, self.g(rs) | imm16)
        elif op == 14:
            name = 'xori'; self.s(rt, self.g(rs) ^ imm16)
        elif op == 15:
            name = 'lui'; self.s(rt, u32(imm16 << 16))
        elif op == 0x20:
            name = 'lb'
            b = self.rd8(u32(self.g(rs) + simm16))
            self.s(rt, b - 0x100 if b >= 0x80 else b)
        elif op == 0x21:
            name = 'lh'
            h = self.rd16(u32(self.g(rs) + simm16))
            self.s(rt, h - 0x10000 if h >= 0x8000 else h)
        elif op == 0x22:
            name = 'lwl'; self.s(rt, self.rd32(u32(self.g(rs) + simm16)))
        elif op == 0x23:
            name = 'lw'; self.s(rt, self.rd32(u32(self.g(rs) + simm16)))
        elif op == 0x24:
            name = 'lbu'; self.s(rt, self.rd8(u32(self.g(rs) + simm16)))
        elif op == 0x25:
            name = 'lhu'; self.s(rt, self.rd16(u32(self.g(rs) + simm16)))
        elif op == 0x26:
            name = 'lwr'; self.s(rt, self.rd32(u32(self.g(rs) + simm16)))
        elif op == 0x28:
            name = 'sb'; self.wr8(u32(self.g(rs) + simm16), self.g(rt))
        elif op == 0x29:
            name = 'sh'; self.wr16(u32(self.g(rs) + simm16), self.g(rt))
        elif op == 0x2a:
            name = 'swl'; self.wr32(u32(self.g(rs) + simm16), self.g(rt))
        elif op == 0x2b:
            name = 'sw'; self.wr32(u32(self.g(rs) + simm16), self.g(rt))
        elif op == 28:
            name, dummy = self.op_special2(funct, rs, rt, nxt)
        else:
            raise RuntimeError('illegal-opcode pc=0x%08x op=%d' % (curr, op))

        self.pc = nxt
        self.log.append('pc=0x%08x op=%s' % (curr, name))
        self.log.extend(self._extra)

    def op_special(self, funct, rs, rt, rd, shamt, nxt):
        if funct == 0x00:
            self.s(rd, self.g(rt) << shamt); return 'sll', nxt
        if funct == 0x02:
            self.s(rd, self.g(rt) >> shamt); return 'srl', nxt
        if funct == 0x03:
            self.s(rd, u32(s32(self.g(rt)) >> shamt)); return 'sra', nxt
        if funct == 0x04:
            self.s(rd, self.g(rt) << (self.g(rs) & 31)); return 'sllv', nxt
        if funct == 0x06:
            self.s(rd, self.g(rt) >> (self.g(rs) & 31)); return 'srlv', nxt
        if funct == 0x07:
            self.s(rd, u32(s32(self.g(rt)) >> (self.g(rs) & 31))); return 'srav', nxt
        if funct == 0x08:
            return 'jr', self.g(rs)
        if funct == 0x09:
            self.s(31, nxt); return 'jalr', self.g(rs)
        if funct == 0x10:
            self.s(rd, self.hi); return 'mfhi', nxt
        if funct == 0x11:
            self.hi = self.g(rs); return 'mthi', nxt
        if funct == 0x12:
            self.s(rd, self.lo); return 'mflo', nxt
        if funct == 0x13:
            self.lo = self.g(rs); return 'mtlo', nxt
        if funct == 0x0c:
            return self.op_syscall(nxt)
        if funct == 0x20:
            self.s(rd, u32(s32(self.g(rs)) + s32(self.g(rt)))); return 'add', nxt
        if funct == 0x21:
            self.s(rd, self.g(rs) + self.g(rt)); return 'addu', nxt
        if funct == 0x22:
            self.s(rd, u32(s32(self.g(rs)) - s32(self.g(rt)))); return 'sub', nxt
        if funct == 0x23:
            self.s(rd, self.g(rs) - self.g(rt)); return 'subu', nxt
        if funct == 0x24:
            self.s(rd, self.g(rs) & self.g(rt)); return 'and', nxt
        if funct == 0x25:
            self.s(rd, self.g(rs) | self.g(rt)); return 'or', nxt
        if funct == 0x26:
            self.s(rd, self.g(rs) ^ self.g(rt)); return 'xor', nxt
        if funct == 0x27:
            self.s(rd, u32(~(self.g(rs) | self.g(rt)))); return 'nor', nxt
        if funct == 0x2a:
            self.s(rd, 1 if s32(self.g(rs)) < s32(self.g(rt)) else 0); return 'slt', nxt
        if funct == 0x2b:
            self.s(rd, 1 if self.g(rs) < self.g(rt) else 0); return 'sltu', nxt
        raise RuntimeError('illegal-opcode pc=0x%08x funct=%d' % (self.cur, funct))

    def op_regimm(self, rs, rt, simm16, nxt):
        if rt == 0x00:      # bltz
            if s32(self.g(rs)) < 0:
                return 'bltz', u32(nxt + (simm16 << 2))
            return 'bltz', nxt
        if rt == 0x01:      # bgez
            if s32(self.g(rs)) >= 0:
                return 'bgez', u32(nxt + (simm16 << 2))
            return 'bgez', nxt
        if rt == 0x10:      # bltzal
            self.s(31, nxt)
            if s32(self.g(rs)) < 0:
                return 'bltzal', u32(nxt + (simm16 << 2))
            return 'bltzal', nxt
        if rt == 0x11:      # bgezal
            self.s(31, nxt)
            if s32(self.g(rs)) >= 0:
                return 'bgezal', u32(nxt + (simm16 << 2))
            return 'bgezal', nxt
        raise RuntimeError('illegal-opcode pc=0x%08x regimm=%d' % (self.cur, rt))

    def op_special2(self, funct, rs, rt, nxt):
        if funct == 0x00:   # mult
            self.lo = u32(s32(self.g(rs)) * s32(self.g(rt)))
            self.hi = 0
            return 'mult', nxt
        if funct == 0x01:   # multu
            self.lo = u32(self.g(rs) * self.g(rt))
            self.hi = 0
            return 'multu', nxt
        if funct == 0x02:   # div
            num, den = s32(self.g(rs)), s32(self.g(rt))
            if den == 0:
                self.lo = 0; self.hi = 0
            else:
                self.lo = u32(int(num / den)); self.hi = u32(num % den)
            return 'div', nxt
        if funct == 0x03:   # divu
            num, den = self.g(rs), self.g(rt)
            if den == 0:
                self.lo = 0; self.hi = 0
            else:
                self.lo = num // den; self.hi = num % den
            return 'divu', nxt
        raise RuntimeError('illegal-opcode pc=0x%08x special2=%d' % (self.cur, funct))

    def op_syscall(self, nxt):
        n = self.g(2)
        a0, a1, a2 = self.g(4), self.g(5), self.g(6)
        if n == 4001:       # exit(code)
            self.exited = True
            self.exitcode = s32(a0) & 0xFFFFFFFF
            self._extra.append('syscall exit code=%d' % s32(a0))
            return 'syscall', self.pc
        if n == 4004:       # write(fd, addr, count)
            if a0 == 1:
                data = bytearray()
                for i in range(a2):
                    data.append(self.rd8(a1 + i))
                self.stdout += data
                self.s(2, len(data))
                self._extra.append('syscall write fd=1 addr=0x%08x count=%d' % (a1, a2))
            else:
                self.s(2, 0)
                self._extra.append('syscall write fd=%d addr=0x%08x count=%d' % (a0, a1, a2))
            return 'syscall', nxt
        if n == 4003:       # read(fd, addr, count)
            got = 0
            if a0 == 0:
                chunk = self.stdin[self.sinpos:self.sinpos + a2]
                self.wrbytes(a1, chunk)
                got = len(chunk)
                self.sinpos += got
            self.s(2, got)
            self._extra.append('syscall read fd=0 addr=0x%08x count=%d done=%d' % (a1, a2, got))
            return 'syscall', nxt
        self.s(2, 0xFFFFFFFF)
        self._extra.append('syscall unknown n=%d' % n)
        return 'syscall', nxt


def main():
    args = sys.argv[1:]
    mode = 'plain'
    stdin = b''
    elf = None
    i = 0
    while i < len(args):
        a = args[i]
        if a == '--trace':
            mode = 'trace'
        elif a == '--snapshot':
            mode = 'snapshot'
        elif a == '--stdin':
            stdin = open(args[i + 1], 'rb').read(); i += 1
        else:
            elf = a
        i += 1

    vm = VM(stdin=stdin)
    vm.load_elf(elf)
    vm.run()

    if mode == 'trace':
        sys.stdout.write('\n'.join(vm.log))
        sys.stdout.write('\nexit status=%d\n' % vm.exitcode)
        sys.exit(vm.exitcode)
    if mode == 'snapshot':
        sys.stdout.write(json.dumps({'pc': u32(vm.pc), 'regs': [u32(x) for x in vm.r]}, separators=(',', ':')))
        sys.stdout.write('\n')
        sys.exit(0)
    sys.stdout.buffer.write(bytes(vm.stdout))
    sys.exit(vm.exitcode)


if __name__ == '__main__':
    main()