#!/usr/bin/env python3
"""elf/sym/solver behaviour checks for elm-yonder hidden cases.

Run as: python3 /tests/verify.py /tests/hidden
Exits non-zero on any failure; prints nothing on success.
"""
import json
import os
import subprocess
import sys

H = sys.argv[1]


# ---- sym condition evaluator (mirror of /app/sym.py grammar) ---------------
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
        raise ValueError("token %r" % c)
    return toks


class P:
    def __init__(self, t):
        self.t = t
        self.i = 0

    def peek(self):
        return self.t[self.i] if self.i < len(self.t) else None

    def take(self):
        x = self.t[self.i]
        self.i += 1
        return x

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
            raise ValueError("end")
        if k[0] == "num":
            return ("num", self.take()[1])
        if k[0] == "id":
            return ("var", self.take()[1])
        if k[0] == "(":
            self.take()
            v = self.expr()
            if not (self.peek() and self.peek()[0] == ")"):
                raise ValueError(")")
            self.take()
            return v
        raise ValueError("tok")

    def cond(self):
        left = self.expr()
        k = self.peek()
        if not (k and k[0] == "cmp"):
            raise ValueError("cmp")
        op = self.take()[1]
        return ("c", op, left, self.expr())


def ev(ast, env):
    t = ast[0]
    if t == "num":
        return ast[1]
    if t == "var":
        return env[ast[1]]
    if t == "b":
        op, a, b = ast[1], ev(ast[2], env), ev(ast[3], env)
        return {"add": a + b, "sub": a - b, "mul": a * b}[op]
    if t == "c":
        a, b = ev(ast[2], env), ev(ast[3], env)
        return {"<": a < b, "<=": a <= b, ">": a > b, ">=": a >= b,
                "==": a == b, "!=": a != b}[ast[1]]
    raise ValueError("ast")


def eval_cond(s, env):
    return ev(P(tokenize(s)).cond(), env)


# ---- 3) ELF parse: exact equality with per-fixture expected JSON ------------
for name in ("alpha", "beta", "gulf"):
    elf = os.path.join(H, "elf", name + ".elf")
    exp = json.load(open(os.path.join(H, "elf", name + ".expected.json")))
    r = subprocess.run(["python3", "/app/elf.py", elf],
                       capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit("elf rc nonzero: " + name)
    got = json.loads(r.stdout)
    if got != exp:
        sys.exit("elf mismatch: " + name)

# ---- 4) symbolic engine: every branch covered both ways, inputs valid -------
module = json.load(open(os.path.join(H, "sym", "alt.sym")))
r = subprocess.run(["python3", "/app/sym.py", os.path.join(H, "sym", "alt.sym")],
                   capture_output=True, text=True)
if r.returncode != 0:
    sys.exit("sym rc nonzero")
out = json.loads(r.stdout)
vars_ = module["vars"]
lo, hi = module["range"]
if out["vars"] != vars_ or out["range"] != [lo, hi]:
    sys.exit("sym header mismatch")
cond_by_id = {g["id"]: g["cond"] for g in module["gates"]}
seen = {g["id"]: set() for g in module["gates"]}
for entry in out["coverage"]:
    gid = entry["gate"]
    truth = bool(entry["truth"])
    inp = entry["input"]
    if gid not in cond_by_id:
        sys.exit("unknown gate")
    if len(inp) != len(vars_):
        sys.exit("input arity")
    for v in inp:
        if not isinstance(v, int) or v < lo or v > hi:
            sys.exit("input out of range")
    if eval_cond(cond_by_id[gid], dict(zip(vars_, inp))) != truth:
        sys.exit("coverage truth mismatch: " + gid)
    seen[gid].add(truth)
for gid, truths in seen.items():
    if truths != {True, False}:
        sys.exit("gate not covered both: " + gid + " " + str(truths))

# ---- 5) solver: verdicts on a sat + unsat + narrow sat query ---------------
expected = {"sat": "sat", "unsat": "unsat", "narrow": "sat"}
for name, want in expected.items():
    p = os.path.join(H, "solver", name + ".smt2")
    data = open(p, "rb").read()
    r = subprocess.run(["python3", "/app/solver.py"], input=data,
                       capture_output=True)
    if r.returncode != 0:
        sys.exit("solver rc nonzero: " + name)
    outtxt = r.stdout.decode("utf-8", "replace")
    if want not in outtxt.split():
        sys.exit("solver verdict wrong: " + name + " " + repr(outtxt))

print("verify-ok")
