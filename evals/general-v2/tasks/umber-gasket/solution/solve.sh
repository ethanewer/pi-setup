#!/bin/bash
# Oracle for umber-gasket: builds the four deliverables under /app by doing the
# real work (writing the M evaluator, generating the knight-move regex rules,
# synthesizing the gate network, and writing the gate evaluator). Never reads
# /tests.
set -euo pipefail

# -------------------------------------------------------------- /app/eval.py
cat > /app/eval.py <<'PYEOF'
#!/usr/bin/env python3
"""umber-gasket /app/eval.py -- a small Scheme-like evaluator (language M).

Contract:
  * stdin line 1            : absolute path of the .m program file to run
  * remaining stdin lines   : relayed to that program, consumed by (read-int),
                              (read) and (eof?)
  * output                  : everything the program prints with (print) goes
                              to stdout.

The evaluator is a full M evaluator (lists, quote, closures, recursion, apply)
so it is able to run a self-interpreter written in M (a meta program that
re-implements the kernel and evaluates a data-encoded subject expression).
"""
import sys
import os


class String(str):
    pass


def _tokenize(s):
    s = s.replace("'", " ' ").replace("(", " ( ").replace(")", " ) ")
    return [t for t in s.split()]


def _atom(tok):
    if tok == "#t":
        return True
    if tok == "#f":
        return False
    if len(tok) >= 2 and tok.startswith('"') and tok.endswith('"'):
        return String(tok[1:-1])
    try:
        return int(tok)
    except ValueError:
        return tok


def _parse(toks):
    if not toks:
        return None
    t = toks.pop(0)
    if t == "(":
        lst = []
        while toks and toks[0] != ")":
            lst.append(_parse(toks))
        if toks and toks[0] == ")":
            toks.pop(0)
        else:
            raise ValueError("unbalanced parens")
        return lst
    if t == ")":
        raise ValueError("unexpected )")
    if t == "'":
        return ["quote", _parse(toks)]
    return _atom(t)


def parse_program(src):
    src = "\n".join(ln for ln in src.splitlines()
                    if not ln.lstrip().startswith(";"))
    toks = _tokenize(src)
    out = []
    while toks:
        out.append(_parse(toks))
    return out


def m_repr(v):
    if v is True:
        return "#t"
    if v is False:
        return "#f"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, String):
        return '"%s"' % v
    if isinstance(v, (tuple, list)):
        return "(" + " ".join(m_repr(x) for x in v) + ")"
    if isinstance(v, str):
        return v
    return str(v)


class Function:
    def __init__(self, params, body, env, name=None):
        self.params = params
        self.body = body
        self.env = env
        self.name = name

    def __repr__(self):
        return "#<closure%s>" % ((" " + self.name) if self.name else "")


class Env(dict):
    def __init__(self, parent=None):
        super().__init__()
        self.parent = parent

    def find(self, name):
        if name in self:
            return self[name]
        if self.parent is not None:
            return self.parent.find(name)
        raise NameError("unbound symbol %r" % name)


class Stream:
    def __init__(self, lines):
        self.lines = list(lines)

    def next_line(self):
        if not self.lines:
            return None
        return self.lines.pop(0)

    def eof(self):
        return not self.lines


class Interp:
    def __init__(self, stream):
        self.stream = stream if stream is not None else Stream([])
        self.global_env = Env(None)
        self._install()

    def _install(self):
        g = self.global_env

        def b(name, fn):
            g[name] = fn

        def aop(op):
            def f(args):
                xs = [x for x in args]
                r = xs[0]
                for x in xs[1:]:
                    if op == "+":
                        r += x
                    elif op == "*":
                        r *= x
                    elif op == "-":
                        r -= x
                    else:
                        r //= x
                return r
            return f
        for op in ("+", "-", "*", "/"):
            b(op, aop(op))

        def rel(op):
            def f(args):
                a, bb = args[0], args[1]
                if op == "=":
                    return a == bb
                if op == "<":
                    return a < bb
                if op == ">":
                    return a > bb
                if op == "<=":
                    return a <= bb
                return a >= bb
            return f
        for op in ("=", "<", ">", "<=", ">="):
            b(op, rel(op))

        b("eq?", lambda a: (a[0] == a[1]))
        b("not", lambda a: not a[0])
        b("car", lambda a: (a[0][0] if isinstance(a[0], list) else None))
        b("cdr", lambda a: (a[0][1:] if isinstance(a[0], list) else None))
        b("cons", lambda a: [a[0]] + list(a[1]))
        b("null?", lambda a: a[0] == [])
        b("pair?", lambda a: isinstance(a[0], list))
        b("list?", lambda a: isinstance(a[0], list))
        b("number?", lambda a: isinstance(a[0], int))
        b("symbol?", lambda a: isinstance(a[0], str) and not isinstance(a[0], String))
        b("string?", lambda a: isinstance(a[0], String))
        b("list", lambda a: list(a))
        b("read", lambda a: self._read(False))
        b("read-string", lambda a: self._read(True))
        b("read-int", lambda a: self._read_int())
        b("eof?", lambda a: self.stream.eof())
        b("print", lambda a: (sys.stdout.write(m_repr(a[0]) + "\n"), True)[1])
        b("display", lambda a: (sys.stdout.write(m_repr(a[0])), True)[1])
        b("apply", lambda a: self._apply(a[0], list(a[1])))

    def _read(self, as_string):
        v = self.stream.next_line()
        return String(v) if v is not None else False

    def _read_int(self):
        v = self.stream.next_line()
        if v is None:
            return False
        try:
            return int(v.strip())
        except ValueError:
            return False

    def _apply(self, fn, arglist):
        if isinstance(fn, Function):
            env = Env(fn.env)
            for p, a in zip(fn.params, arglist):
                env[p] = a
            return self.eval_block(fn.body, env)
        if callable(fn):
            return fn(arglist)
        raise TypeError("apply to non-function")

    def eval_program(self, src):
        exps = parse_program(src)
        return self.eval_block(exps, self.global_env)

    def eval_block(self, exps, env):
        last = None
        for e in exps:
            last = self.eval(e, env)
        return last

    def eval(self, expr, env):
        if isinstance(expr, int) or isinstance(expr, bool) or isinstance(expr, String):
            return expr
        if isinstance(expr, str):
            return env.find(expr)
        if not isinstance(expr, list) or not expr:
            return expr
        head = expr[0]
        if head == "quote":
            return expr[1]
        if head == "if":
            c = self.eval(expr[1], env)
            if c is not False and c is not None:
                return self.eval(expr[2], env)
            return self.eval(expr[3], env) if len(expr) > 3 else False
        if head == "begin":
            return self.eval_block(expr[1:], env)
        if head == "define":
            name = expr[1]
            if isinstance(name, list):
                env[name[0]] = Function(name[1:], expr[2:], env)
                return env[name[0]]
            val = self.eval(expr[2], env) if len(expr) > 2 else None
            env[name] = val
            return val
        if head == "lambda":
            return Function(expr[1], expr[2:], env)
        fn = self.eval(expr[0], env)
        args = [self.eval(a, env) for a in expr[1:]]
        return self._apply(fn, args)


def run_engine():
    first = sys.stdin.readline()
    first = first.strip()
    if not first:
        sys.stderr.write("first stdin line must name a program file\n")
        sys.exit(1)
    relay = [ln.strip("\n") for ln in sys.stdin]
    if not os.path.exists(first):
        sys.stderr.write("program file not found: %s\n" % first)
        sys.exit(1)
    with open(first) as fh:
        src = fh.read()
    interp = Interp(Stream(relay))
    try:
        interp.eval_program(src)
    except Exception as e:
        sys.stderr.write("eval error: %r\n" % e)
        sys.exit(2)
    sys.exit(0)


if __name__ == "__main__":
    run_engine()
PYEOF
chmod +x /app/eval.py

# ----------------------------------------- /app/moves.fen.rules (generated)
python3 - <<'PYEOF'
import json

OPS = [(2, 1), (2, -1), (-2, 1), (-2, -1),
       (1, 2), (1, -2), (-1, 2), (-1, -2)]


def empty_board(r, c):
    b = [["."] * 8 for _ in range(8)]
    b[r][c] = "N"
    return b


def to_fen(b):
    parts = []
    for row in b:
        s = []
        cnt = 0
        for ch in row:
            if ch == ".":
                cnt += 1
            else:
                if cnt:
                    s.append(str(cnt)); cnt = 0
                s.append(ch)
        if cnt:
            s.append(str(cnt))
        parts.append("".join(s))
    return "/".join(parts) + " w - - 0 1"


def legal_moves(src_fen):
    b = src_fen.split()[0]
    ranks = b.split("/")
    board = []
    for rank in ranks:
        row = []
        for ch in rank:
            if ch.isdigit():
                row += ["."] * int(ch)
            else:
                row.append(ch)
        board.append(row)
    sr = sc = None
    for r in range(8):
        for c in range(8):
            if board[r][c] == "N":
                sr, sc = r, c
    if sr is None:
        return []
    out = []
    for dr, dc in OPS:
        nr, nc = sr + dr, sc + dc
        if 0 <= nr < 8 and 0 <= nc < 8 and board[nr][nc] == ".":
            b2 = [list(x) for x in board]
            b2[sr][sc] = "."
            b2[nr][nc] = "N"
            out.append(to_fen(b2))
    return out


rules = []
for r in range(8):
    for c in range(8):
        src = to_fen(empty_board(r, c))
        for tgt in legal_moves(src):
            rules.append([src, tgt])
json.dump(rules, open("/app/moves.fen.rules", "w"))
print("moves.fen.rules rules=%d" % len(rules))
PYEOF

# --------------------------- /app/gate_net.txt + /app/simulate.py (synthesized)
python3 - <<'PYEOF'
import math

NI, NO = 7, 8


def fib(k):
    a, b = 1, 1
    for _ in range(k):
        a, b = b, a + b
    return a


FIB = [fib(i) for i in range(14)]


def net_value(n):
    return FIB[math.isqrt(n)]


_counter = [0]


def new(expr, body):
    _counter[0] += 1
    body.append("w%d = %s" % (_counter[0], expr))
    return "w%d" % _counter[0]


body = []
for i in range(NI):
    body.append("nn%d = ~ n%d" % (i, i))
for bit in range(NO):
    terms = [v for v in range(1 << NI) if (net_value(v) >> bit) & 1]
    if not terms:
        body.append("f%d = 0" % bit)
        continue
    ands = []
    for v in terms:
        lit = ["n%d" % i if (v >> i) & 1 else "nn%d" % i for i in range(NI)]
        cur = lit[0]
        for L in lit[1:]:
            cur = new("& %s %s" % (cur, L), body)
        ands.append(cur)
    cur = ands[0]
    for a in ands[1:]:
        cur = new("| %s %s" % (cur, a), body)
    body.append("f%d = %s" % (bit, cur))

header = ["INPUTS " + " ".join("n%d" % i for i in range(NI)),
          "OUTPUTS " + " ".join("f%d" % i for i in range(NO))]
open("/app/gate_net.txt", "w").write("\n".join(header + body) + "\n")
print("gate_net.txt lines=%d" % len(body))
PYEOF

cat > /app/simulate.py <<'PYEOF'
#!/usr/bin/env python3
"""umber-gasket /app/simulate.py -- evaluate /app/gate_net.txt (a flat
combinational net) on an integer input n and print GateNet(n).

usage: python3 simulate.py <netfile> <n>
"""
import sys


def parse_net(text):
    lines = [ln.strip() for ln in text.splitlines() if ln.strip()]
    ins = lines[0].split()[1:]
    outs = lines[1].split()[1:]
    expr = {}
    for ln in lines[2:]:
        lhs, sep, rest = ln.partition("=")
        if not sep:
            continue
        expr[lhs.strip()] = rest.strip()
    return ins, outs, expr


def eval_net(text, n):
    ins, outs, expr = parse_net(text)
    memo = {}
    for i, name in enumerate(ins):
        memo[name] = (n >> i) & 1
    sys.setrecursionlimit(400000)

    def solve(w):
        if w in memo:
            return memo[w]
        ws = expr[w].split()
        if len(ws) == 1 and ws[0] in ("0", "1"):
            v = int(ws[0])
        elif len(ws) == 1:
            v = solve(ws[0])
        elif ws[0] == "~":
            v = 1 - solve(ws[1])
        else:
            a, b = solve(ws[1]), solve(ws[2])
            v = (a & b) if ws[0] == "&" else ((a | b) if ws[0] == "|" else (a ^ b))
        memo[w] = v
        return v

    res = 0
    for i, o in enumerate(outs):
        res |= solve(o) << i
    return res


def main():
    if len(sys.argv) != 3:
        sys.stderr.write("usage: simulate.py <netfile> <n>\n")
        sys.exit(2)
    text = open(sys.argv[1]).read()
    n = int(sys.argv[2])
    print(eval_net(text, n))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
PYEOF
chmod +x /app/simulate.py

echo "umber-gasket deliverables produced" >&2