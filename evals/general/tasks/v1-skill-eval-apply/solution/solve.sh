#!/bin/bash
set -euo pipefail

cat > /app/interp.py <<'PYEOF'
import json, re, sys

def tokenize(s):
    return s.replace('(', ' ( ').replace(')', ' ) ').split()

def parse(tokens):
    tok = tokens.pop(0)
    if tok == '(':
        lst = []
        while tokens[0] != ')':
            lst.append(parse(tokens))
        tokens.pop(0)
        return lst
    elif tok == ')':
        raise SyntaxError('unexpected )')
    else:
        try:
            return int(tok)
        except ValueError:
            return tok

BUILTINS = {
    'add': lambda args: args[0] + args[1],
    'sub': lambda args: args[0] - args[1],
    'mul': lambda args: args[0] * args[1],
    'div': lambda args: (abs(args[0]) // abs(args[1])) * (1 if (args[0] >= 0) == (args[1] >= 0) else -1),
}

class Env(dict):
    def __init__(self, *a, **k):
        super().__init__(*a, **k)
        self.update({n: f for n, f in BUILTINS.items()})

def make_proc(params, body, env):
    def proc(args):
        child = Env(env)
        for p, v in zip(params, args):
            child[p] = v
        return evaluate(body, child)
    return proc

def evaluate(expr, env):
    if isinstance(expr, int):
        return expr
    if isinstance(expr, str):
        if expr in env:
            return env[expr]
        raise ValueError('undefined symbol: ' + expr)
    head, *rest = expr
    if head == 'if':
        cond, then_e, else_e = rest
        return evaluate(then_e, env) if evaluate(cond, env) else evaluate(else_e, env)
    if head == 'lambda':
        params, body = rest
        return make_proc(params, body, env)
    if head == 'define':
        target, body = rest
        if isinstance(target, list):
            fname, params = target[0], target[1:]
            env[fname] = make_proc(params, body, env)
        else:
            env[target] = evaluate(body, env)
        return None
    # generic application
    fn = evaluate(head, env)
    args = [evaluate(a, env) for a in rest]
    return apply(fn, args)

def apply(fn, args):
    return fn(args)

with open('/app/prog.lisp') as f:
    src = f.read()
tokens = tokenize(src)
forms = []
while tokens:
    forms.append(parse(tokens))
env = Env()
result = None
for form in forms:
    r = evaluate(form, env)
    if r is not None:
        result = r
with open('/app/result.json', 'w') as f:
    json.dump({'value': result}, f)
PYEOF

python3 /app/interp.py