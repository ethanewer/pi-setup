#!/usr/bin/python3
"""symxe: a compact LLVM-bitcode symbolic execution engine.

Reads an LLVM bitcode (.bc) or textual IR (.ll) module, symbolically executes
the integer (i32) subset emitted by `clang -O0` for the function named
`target`, and prints one concrete test case per reachable terminal path.

That small interpreter paired with the z3 SMT solver is a self-contained
concolic executor over the arithmetic/branching subset the task fixtures use.

Output contract:
    PATHS <n>
    TEST <v0> <v1> ...        # one line per terminal path, values in param order
and, for bookkeeping:
    --version  ->  "symxe <version>"

Exit status: 0 on success; non-zero on any error (including unreadable or
non-bitcode input, or a missing @target function).
"""
import subprocess, sys, re, os
import z3
from z3 import *
SAT = z3.sat

VERSION = "1.0"
FUNC = "target"


def llvm_dis(path):
    if path.endswith(".ll"):
        return open(path).read()
    try:
        r = subprocess.run(["llvm-dis", "-o", "-", path],
                           capture_output=True, text=True, timeout=30)
    except Exception as e:
        sys.stderr.write("symxe: cannot disassemble %s: %s\n" % (path, e))
        sys.exit(3)
    if r.returncode != 0:
        sys.stderr.write("symxe: llvm-dis failed on %s: %s\n" % (path, r.stderr[:300]))
        sys.exit(2)
    return r.stdout


def parse_module(text):
    m = re.search(r'define\s+[^{;]*@%s\s*\(([^)]*)\)[^{;]*\{' % FUNC, text, re.S)
    if not m:
        return None, None, None
    params = re.findall(r'%\w+', m.group(1))
    start = m.end() - 1
    depth = 0
    end = start
    for j in range(start, len(text)):
        c = text[j]
        if c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                end = j
                break
    body = text[start + 1:end]
    blocks = {}
    order = []
    cur_label = None
    pending = []
    for line in body.splitlines():
        line = line.split(';')[0].strip()
        ls = re.match(r'^([A-Za-z0-9_.$][\w.$]*):\s*$', line)
        if ls:
            if cur_label is None and pending:
                blocks['__entry__'] = pending
                order.append('__entry__')
                pending = []
            cur_label = ls.group(1)
            blocks[cur_label] = []
            order.append(cur_label)
        elif line:
            if cur_label is None:
                pending.append(line)
            else:
                blocks[cur_label].append(line)
    if cur_label is None and pending:
        blocks['__entry__'] = pending
        order = ['__entry__']
    return params, blocks, order


def is_sat(exprs):
    s = Solver()
    for e in exprs:
        s.add(e)
    return s.check() == SAT


class Slot:
    _n = 0

    def __init__(self):
        Slot._n += 1
        self.id = Slot._n

    def __hash__(self):
        return hash(self.id)

    def __eq__(self, o):
        return isinstance(o, Slot) and o.id == self.id


def fresh():
    return BitVecVal(0, 32)


def i2sigm(v):
    if v >= 2 ** 31:
        v -= 2 ** 32
    return v


def run_engine(text, params):
    rp, blocks, order = parse_module(text)
    if rp is None:
        sys.stderr.write("symxe: no function named @%s found\n" % FUNC)
        sys.exit(4)
    params = rp
    entry = order[0]
    reg0 = {}
    for name in params:
        reg0[name] = BitVec(name + '_sym', 32)
    outcomes = []
    from collections import deque
    work = deque()
    work.append((entry, 0, dict(reg0), {}, []))
    steps = 0
    while work:
        steps += 1
        if steps > 20000:
            sys.stderr.write("symxe: exploration cap exceeded\n")
            sys.exit(5)
        label, pc, reg, mem, cons = work.popleft()
        while True:
            if label not in blocks or pc >= len(blocks[label]):
                break
            inst = blocks[label][pc]
            m_alloca = re.match(r'^%\S+\s*=\s*alloca\s+i\S+', inst)
            m_load = re.match(r'^(\S+)\s*=\s*load\s+i\d+,\s*ptr\s+(%\w+)', inst)
            m_store = re.match(r'^store\s+i\d+\s+(.+?),\s*ptr\s+(%\w+)', inst)
            m_air = re.match(r'^(\S+)\s*=\s*(add|sub|mul|shl|lshr|ashr|and|or|xor)[ \t]*(?:nsw|nuw|exact)?[ \t]*i\d+[ \t]+(.+?),\s*(.+)$', inst)
            m_icmp = re.match(r'^(\S+)\s*=\s*icmp\s+(eq|ne|sgt|sge|slt|sle|ugt|uge|ult|ule)[ \t]*i\d+[ \t]+(.+?),\s*(.+)$', inst)
            m_ret = re.match(r'^ret\s+i\d+\s+(.+)$', inst)
            m_br = re.match(r'^br\s+i1\s+(%\w+),\s*label\s+%(\S+),\s*label\s+%(\S+)$', inst)
            m_bru = re.match(r'^br\s+label\s+%(\S+)$', inst)

            def operand(s, reg):
                s = s.strip()
                if re.match(r'^%\w+$', s):
                    v = reg.get(s)
                    if v is None:
                        raise RuntimeError('unknown reg ' + s)
                    return v
                if re.match(r'^-?\d+$', s):
                    return BitVecVal(int(s), 32)
                raise RuntimeError('unsupported operand ' + s)

            if m_alloca:
                res = m_alloca.group(0).split('=')[0].strip()
                reg[res] = Slot()
                pc += 1
                continue
            if m_load:
                res, ptr = m_load.group(1), m_load.group(2)
                slot = reg.get(ptr)
                val = mem.get(slot)
                reg[res] = val if val is not None else fresh()
                pc += 1
                continue
            if m_store:
                val, ptr = m_store.group(1), m_store.group(2)
                slot = reg.get(ptr)
                if slot is not None:
                    mem[slot] = operand(val, reg)
                pc += 1
                continue
            if m_air:
                res, op, a, b = m_air.group(1), m_air.group(2), m_air.group(3), m_air.group(4)
                A, B = operand(a, reg), operand(b, reg)
                if op == 'add':
                    V = A + B
                elif op == 'sub':
                    V = A - B
                elif op == 'mul':
                    V = A * B
                elif op == 'shl':
                    V = A << B
                elif op == 'lshr':
                    V = LShR(A, B)
                elif op == 'ashr':
                    V = A >> B
                elif op == 'and':
                    V = A & B
                elif op == 'or':
                    V = A | B
                elif op == 'xor':
                    V = A ^ B
                reg[res] = V
                pc += 1
                continue
            if m_icmp:
                res, op, a, b = m_icmp.group(1), m_icmp.group(2), m_icmp.group(3), m_icmp.group(4)
                A, B = operand(a, reg), operand(b, reg)
                if op == 'eq':
                    V = A == B
                elif op == 'ne':
                    V = A != B
                elif op == 'sgt':
                    V = A > B
                elif op == 'sge':
                    V = A >= B
                elif op == 'slt':
                    V = A < B
                elif op == 'sle':
                    V = A <= B
                elif op == 'ugt':
                    V = UGT(A, B)
                elif op == 'uge':
                    V = UGE(A, B)
                elif op == 'ult':
                    V = ULT(A, B)
                elif op == 'ule':
                    V = ULE(A, B)
                reg[res] = V
                pc += 1
                continue
            if m_ret:
                v = operand(m_ret.group(1), reg)
                if is_sat(cons):
                    outcomes.append((v, list(cons)))
                break
            if m_br:
                c = reg.get(m_br.group(1))
                A, B = m_br.group(2), m_br.group(3)
                for (tgt, ex) in ((A, c), (B, Not(c))):
                    if is_sat(cons + [ex]):
                        work.append((tgt, 0, dict(reg), dict(mem), cons + [ex]))
                break
            if m_bru:
                label = m_bru.group(1)
                pc = 0
                continue
            sys.stderr.write("symxe: unsupported instruction in @%s: %s\n" % (FUNC, inst))
            sys.exit(6)
    return outcomes, params


def main():
    if len(sys.argv) >= 2 and sys.argv[1] == '--version':
        print("symxe %s" % VERSION)
        sys.exit(0)
    if len(sys.argv) < 3 or sys.argv[1] != 'run':
        sys.stderr.write("usage: symxe run <module.bc|module.ll>\n")
        sys.exit(1)
    text = llvm_dis(sys.argv[2])
    outcomes, params = run_engine(text, [])
    print("PATHS %d" % len(outcomes))
    for (rec, cons) in outcomes:
        s = Solver()
        for c in cons:
            s.add(c)
        if s.check() != sat:
            continue
        m = s.model()
        vals = []
        for name in params:
            v = m.eval(BitVec(name + '_sym', 32), model_completion=True).as_long()
            vals.append(str(i2sigm(v)))
        print("TEST " + " ".join(vals))


if __name__ == '__main__':
    main()