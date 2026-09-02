#!/usr/bin/env python3
"""A minimal metacircular Scheme evaluator (env analysis, closures, eval/apply).

Reads whitespace/newline tokenized Scheme source from stdin, evaluates every
top-level form in turn, and prints each resulting value on its own line using
Scheme display notation.  Supported: integer arithmetic (+ - * /), quote,
if, define (incl. named procedures), lambda with lexical closures, begin,
eq?, < >, list?  null? car cdr cons list, and common predicates.

Usage:  python3 scheme.py < program.scm
"""
import sys

# ----------------------------- reader -----------------------------------
def tokenize(src):
    return src.replace("(", " ( ").replace(")", " ) ").split()

def parse(tokens):
    if not tokens:
        raise ValueError("unexpected EOF")
    tok = tokens.pop(0)
    if tok == "(":
        items = []
        while tokens and tokens[0] != ")":
            items.append(parse(tokens))
        if not tokens:
            raise ValueError("missing )")
        tokens.pop(0)
        return items
    if tok == ")":
        raise ValueError("unexpected )")
    try:
        return int(tok)
    except ValueError:
        return tok

# --------------------------- interpreter --------------------------------
def make_env(parent=None):
    return {"parent": parent, "vars": {}}

def lookup(env, name):
    while env is not None:
        if name in env["vars"]:
            return env["vars"][name]
        env = env["parent"]
    raise NameError("unbound: %s" % name)

def define(env, name, val):
    env["vars"][name] = val

def make_proc(params, body, env):
    return ("closure", params, body, env)

def ev_list(vals, env):
    return [evalx(v, env) for v in vals]

def is_true(v):
    # Scheme: only #f is false.
    return v is not False

def apply_proc(proc, args):
    if proc[0] == "closure":
        _, params, body, denv = proc
        env = make_env(denv)
        for p, a in zip(params, args):
            define(env, p, a)
        result = None
        for form in body:
            result = evalx(form, env)
        return result
    if isinstance(proc, str) and proc.startswith("builtin:"):
        fn = proc[len("builtin:"):]
        return _builtin(fn, args)
    raise TypeError("not a procedure: %r" % (proc,))

def _builtin(name, args):
    a = args
    if name == "+":
        return sum(a)
    if name == "-":
        return a[0] - sum(a[1:])
    if name == "*":
        r = 1
        for x in a:
            r *= x
        return r
    if name == "/":
        r = a[0]
        for x in a[1:]:
            r = int(r / x) if r % x == 0 else r // x
        return r
    if name in ("eq?", "="):
        return a[0] == a[1]
    if name == "<":
        return a[0] < a[1]
    if name == ">":
        return a[0] > a[1]
    if name == "car":
        return a[0][0]
    if name == "cdr":
        return a[0][1:]
    if name == "cons":
        return [a[0]] + a[1]
    if name == "list":
        return a
    if name == "null?":
        return a[0] == []
    if name == "list?":
        return isinstance(a[0], list)
    if name == "number?":
        return isinstance(a[0], int)
    raise NameError("unknown builtin: %s" % name)

def evalx(expr, env):
    if isinstance(expr, int):
        return expr
    if isinstance(expr, str):
        return lookup(env, expr)
    if not isinstance(expr, list):
        return expr
    head = expr[0]
    if isinstance(head, str):
        if head == "quote":
            return expr[1]
        if head == "if":
            return evalx(expr[2] if is_true(evalx(expr[1], env)) else expr[3], env)
        if head == "define":
            target = expr[1]
            if isinstance(target, list):
                name = target[0]
                params = target[1:]
                proc = make_proc(params, expr[2:], env)
                define(env, name, proc)
            else:
                define(env, target, evalx(expr[2], env))
            return None
        if head == "lambda":
            return make_proc(expr[1], expr[2:], env)
        if head == "begin":
            result = None
            for form in expr[1:]:
                result = evalx(form, env)
            return result
    proc = evalx(head, env)
    args = ev_list(expr[1:], env)
    return apply_proc(proc, args)

B = {"+": "builtin:+", "-": "builtin:-", "*": "builtin:*", "/": "builtin:/",
     "eq?": "builtin:eq?", "=": "builtin:=", "<": "builtin:<", ">": "builtin:>",
     "car": "builtin:car", "cdr": "builtin:cdr", "cons": "builtin:cons",
     "list": "builtin:list", "null?": "builtin:null?", "list?": "builtin:list?",
     "number?": "builtin:number?", "#t": True, "#f": False}

def to_display(v):
    if v is True:
        return "#t"
    if v is False:
        return "#f"
    if isinstance(v, list):
        if v and isinstance(v[0], str) and v[0] == "closure":
            return "#<procedure>"
        return "(" + " ".join(to_display(x) for x in v) + ")"
    return str(v)

def main():
    global B
    src = sys.stdin.read()
    tokens = tokenize(src)
    global_env = make_env()
    global_env["vars"] = dict(B)
    results = []
    while tokens:
        form = parse(tokens)
        v = evalx(form, global_env)
        if v is not None:
            results.append(to_display(v))
    print("\n".join(results))

if __name__ == "__main__":
    main()
