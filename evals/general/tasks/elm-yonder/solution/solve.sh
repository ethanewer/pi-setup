#!/usr/bin/env bash
# Oracle for elm-yonder: produces /app/link.py, /app/elf.py, /app/sym.py,
# /app/solver.py and builds /app/all.bc with debug metadata, then validates.
set -euo pipefail
cd /app

# ---------------------------------------------------------------- link.py
cat > /app/link.py <<'PYEOF'
#!/usr/bin/env python3
"""Coalesce per-module LLVM IR files into one linkable bitcode module.
Usage: link.py -o OUT.bc IN1.ll [IN2.ll ...]
Runs the system llvm-link over the inputs; works for any set of IR modules.
"""
import argparse
import os
import shutil
import subprocess
import sys


def find_link():
    for name in ("llvm-link-18", "llvm-link-17", "llvm-link-16",
                 "llvm-link-15", "llvm-link"):
        p = shutil.which(name)
        if p:
            return p
    raise SystemExit("no llvm-link tool found on PATH")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-o", "--output", required=True)
    ap.add_argument("inputs", nargs="+")
    args = ap.parse_args()

    tool = find_link()
    out = os.path.abspath(args.output)
    cmd = [tool] + args.inputs + ["-o", out]
    r = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if r.returncode != 0:
        sys.stderr.buffer.write(r.stdout)
        sys.stderr.buffer.write(r.stderr)
        raise SystemExit(r.returncode)


if __name__ == "__main__":
    main()
PYEOF
chmod +x /app/link.py

# ---------------------------------------------------------------- elf.py
cat > /app/elf.py <<'PYEOF'
#!/usr/bin/env python3
"""Parse an ELF header + section-header table and emit an address->32-bit-word
JSON mapping for every data-carrying section.

Usage: elf.py <elf-file>
Supports ELF32 and ELF64 in both byte orders.
"""
import json
import sys


def load(d, o, n, le):
    return int.from_bytes(d[o:o + n], "little" if le else "big")


def parse(path):
    with open(path, "rb") as f:
        d = f.read()
    if d[:4] != b"\x7fELF":
        raise SystemExit("not an ELF file: " + path)

    is64 = d[4] == 2          # EI_CLASS: 1 = ELF32, 2 = ELF64
    le = d[5] == 1            # EI_DATA:  1 = little, 2 = big

    if is64:
        shoff = load(d, 0x28, 8, le)
        shentsize = load(d, 0x3A, 2, le)
        shnum = load(d, 0x3C, 2, le)
    else:
        shoff = load(d, 0x20, 4, le)
        shentsize = load(d, 0x2E, 2, le)
        shnum = load(d, 0x30, 2, le)

    out = {}
    for i in range(shnum):
        base = shoff + i * shentsize
        if base + shentsize > len(d):
            continue
        sh_type = load(d, base + 0x04, 4, le)
        if is64:
            sh_addr = load(d, base + 0x10, 8, le)
            sh_offset = load(d, base + 0x18, 8, le)
            sh_size = load(d, base + 0x20, 8, le)
        else:
            sh_addr = load(d, base + 0x0C, 4, le)
            sh_offset = load(d, base + 0x10, 4, le)
            sh_size = load(d, base + 0x14, 4, le)
        if sh_type == 8:            # SHT_NOBITS holds no file data
            continue
        if sh_size == 0:
            continue
        if sh_offset + sh_size > len(d):
            continue
        nwords = sh_size // 4
        for k in range(nwords):
            word = load(d, sh_offset + 4 * k, 4, le)
            out["0x%x" % (sh_addr + 4 * k)] = word
    return out


def main():
    if len(sys.argv) < 2:
        raise SystemExit("usage: elf.py <elf-file>")
    mapping = parse(sys.argv[1])
    print(json.dumps(mapping, indent=0))


if __name__ == "__main__":
    main()
PYEOF
chmod +x /app/elf.py

# ---------------------------------------------------------------- sym.py
cat > /app/sym.py <<'PYEOF'
#!/usr/bin/env python3
"""A small symbolic engine over a .sym module: for every branch (gate) and each
of its two outcomes, produce a concrete input inside [lo,hi] that triggers it.

Usage: sym.py <module.sym>
Condition grammar: EXPR CMP EXPR; EXPR is +,-,* with * binding tighter,
left-assoc, parentheses; CMP in {<=,>=,==,!=,<,>}.
"""
import json
import sys

import z3


# --- tokenizer + parser -> nested AST --------------------------------------
def tokenize(s):
    toks, i = [], 0
    while i < len(s):
        c = s[i]
        if c.isspace():
            i += 1
            continue
        if c.isdigit() or (c == "-" and i + 1 < len(s) and s[i + 1].isdigit()):
            j = i
            if s[j] == "-":
                j += 1
            while j < len(s) and s[j].isdigit():
                j += 1
            toks.append(("num", int(s[i:j])))
            i = j
            continue
        if c.isalpha() or c == "_":
            j = i
            while j < len(s) and (s[j].isalnum() or s[j] == "_"):
                j += 1
            toks.append(("id", s[i:j]))
            i = j
            continue
        if s[i:i + 2] in ("<=", ">=", "==", "!="):
            toks.append(("cmp", s[i:i + 2]))
            i += 2
            continue
        if c in "<>":
            toks.append(("cmp", c))
            i += 1
            continue
        if c in "+-*()":
            toks.append((c, c))
            i += 1
            continue
        raise ValueError("bad token: %r" % c)
    return toks


class Parser:
    def __init__(self, toks):
        self.t = toks
        self.i = 0

    def peek(self):
        return self.t[self.i] if self.i < len(self.t) else None

    def take(self):
        t = self.t[self.i]
        self.i += 1
        return t

    def expr(self):
        v = self.term()
        while True:
            k = self.peek()
            if k and k[0] in ("+", "-"):
                op = self.take()[1]
                v = ("b", "add" if op == "+" else "sub", v, self.term())
            else:
                return v

    def term(self):
        v = self.factor()
        while True:
            k = self.peek()
            if k and k[0] == "*":
                self.take()
                v = ("b", "mul", v, self.factor())
            else:
                return v

    def factor(self):
        k = self.peek()
        if k is None:
            raise ValueError("unexpected end of expression")
        if k[0] == "num":
            return ("num", self.take()[1])
        if k[0] == "id":
            return ("var", self.take()[1])
        if k[0] == "(":
            self.take()
            v = self.expr()
            if not (self.peek() and self.peek()[0] == ")"):
                raise ValueError("missing )")
            self.take()
            return v
        raise ValueError("unexpected token %r" % (k,))

    def cond(self):
        left = self.expr()
        k = self.peek()
        if not (k and k[0] == "cmp"):
            raise ValueError("condition must contain a comparison")
        op = self.take()[1]
        right = self.expr()
        return ("c", op, left, right)


def parse_cond(s):
    return Parser(tokenize(s)).cond()


def eval_ast(ast, env):
    t = ast[0]
    if t == "num":
        return ast[1]
    if t == "var":
        if ast[1] not in env:
            raise ValueError("undefined variable %s" % ast[1])
        return env[ast[1]]
    if t == "b":
        op, a, b = ast[1], eval_ast(ast[2], env), eval_ast(ast[3], env)
        return {"add": a + b, "sub": a - b, "mul": a * b}[op]
    if t == "c":
        a, b = eval_ast(ast[2], env), eval_ast(ast[3], env)
        return {"<": a < b, "<=": a <= b, ">": a > b, ">=": a >= b,
                "==": a == b, "!=": a != b}[ast[1]]
    raise ValueError(repr(ast))


def zexpr(ast, Z):
    t = ast[0]
    if t == "num":
        return z3.IntVal(ast[1])
    if t == "var":
        return Z[ast[1]]
    if t == "b":
        a, b = zexpr(ast[2], Z), zexpr(ast[3], Z)
        return {"add": a + b, "sub": a - b, "mul": a * b}[ast[1]]
    if t == "c":
        a, b = zexpr(ast[2], Z), zexpr(ast[3], Z)
        return {"<": a < b, "<=": a <= b, ">": a > b, ">=": a >= b,
                "==": a == b, "!=": a != b}[ast[1]]
    raise ValueError(repr(ast))


def main():
    if len(sys.argv) < 2:
        raise SystemExit("usage: sym.py <module.sym>")
    m = json.load(open(sys.argv[1]))
    vars_ = m["vars"]
    lo, hi = m["range"]
    Z = {v: z3.Int(v) for v in vars_}

    coverage = []
    for g in m["gates"]:
        condast = parse_cond(g["cond"])
        cexpr = zexpr(condast, Z)
        for truth in (True, False):
            s = z3.Solver()
            for v in vars_:
                s.add(Z[v] >= lo, Z[v] <= hi)
            s.add(cexpr if truth else z3.Not(cexpr))
            if s.check() == z3.sat:
                model = s.model()
                inp = [model[Z[v]].as_long() for v in vars_]
                coverage.append({"gate": g["id"], "truth": truth, "input": inp})

    out = {"vars": vars_, "range": [lo, hi], "coverage": coverage}
    print(json.dumps(out))


if __name__ == "__main__":
    main()
PYEOF
chmod +x /app/sym.py

# ---------------------------------------------------------------- solver.py
cat > /app/solver.py <<'PYEOF'
#!/usr/bin/env python3
"""Read a quantifier-free bit-vector SMT-LIB script on stdin, solve it with z3,
print the verdict and exit with status 0 on success.

Usage: solver.py < query.smt2
"""
import shutil
import subprocess
import sys


def find_z3():
    for name in ("z3", "z3-18", "z3-17"):
        p = shutil.which(name)
        if p:
            return p
    raise SystemExit("z3 not found on PATH")


def main():
    tool = find_z3()
    data = sys.stdin.buffer.read()
    p = subprocess.run([tool, "-in", "-smt2"], input=data,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    out = p.stdout.decode("utf-8", "replace").strip()
    if out:
        print(out)
    sys.exit(p.returncode)


if __name__ == "__main__":
    main()
PYEOF
chmod +x /app/solver.py

# ---------------------------------------------------------------- deliverables
# Rebuild the C source with debug metadata so its IR carries source-level
# variable/line info, then coalesce all three modules into all.bc.
clang -g -c -emit-llvm /app/src/sample.c -o /app/sample_dbg.ll
python3 /app/link.py -o /app/all.bc /app/module_a.ll /app/module_b.ll /app/sample_dbg.ll

# Self-check each deliverable on the shipped fixtures.
python3 /app/elf.py /app/sample.elf >/dev/null
python3 /app/sym.py /app/prog.sym >/dev/null
python3 /app/solver.py < /app/pow.smt2 >/dev/null

echo "oracle-ok"