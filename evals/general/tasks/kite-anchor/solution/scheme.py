#!/usr/bin/env python3
"""scheme.py — FK81 "Scheme-Lite" metacircular evaluator.

Contract:
    python3 /app/scheme.py < program
Reads a Scheme-Lite program from stdin (a whitespace/newline separated stream of
top-level forms).  Parses the whole stream, evaluates each top-level form in
the shared global environment, and prints the Scheme textual value of every
top-level form EXCEPT definitions (define lets nothing print).  Each printed
value is on its own line, in Scheme notation:

    int              -> "42"
    boolean          -> "#t" / "#f"
    symbol           -> the symbol's name
    list            -> "(a b c)" (recursive, paren-separated with spaces)
    closure          -> "#<procedure>"
    void/None        -> (nothing printed)

Features (metacircular: env chains, closures with capture, eval/apply):
  self-evaluating : ints, #t, #f
  quote / '       : literal
  define          : (define name expr)
  lambda          : (lambda (params) body...)  -> closure capturing env
  if / begin / let
  primitives      : + - * = < > car cdr cons list eq? null? number?
                    boolean? pair? symbol? not
  apply           : (apply proc list)
  eval            : (eval expr)  -> evaluate expr in the global env
"""
import functools
import sys

# ---------------- reader ----------------

class Reader(object):
    def __init__(self, text):
        self.tokens = text.replace('(', ' ( ').replace(')', ' ) ').split()

    def read(self):
        if not self.tokens:
            return None
        tok = self.tokens.pop(0)
        if tok == '(':
            out = []
            while self.tokens and self.tokens[0] != ')':
                out.append(self.read())
            self.tokens.pop(0)  # drop ')'
            return out
        elif tok == ')':
            raise SyntaxError("unexpected )")
        elif tok == "'":
            return ['quote', self.read()]
        return self.atom(tok)

    def atom(self, tok):
        try:
            return int(tok)
        except ValueError:
            return tok


# ---------------- environments ----------------

class Env:
    def __init__(self, outer=None):
        self.d = {}
        self.outer = outer

    def find(self, name):
        e = self
        while e is not None:
            if name in e.d:
                return e
            e = e.outer
        raise NameError("unbound symbol " + name)

    def get(self, name):
        return self.find(name).d[name]

    def set(self, name, val):
        self.d[name] = val


GLOBAL = Env()

# ---------------- primitives ----------------

def add(*a):
    r = 0
    for x in a:
        r += int(x)
    return r


def sub(*a):
    if len(a) == 0:
        raise TypeError
    r = int(a[0])
    for x in a[1:]:
        r -= int(x)
    return r


def mul(*a):
    r = 1
    for x in a:
        r *= int(x)
    return r


def num_lt(*a):
    for x, y in zip(a, a[1:]):
        if not (int(x) < int(y)):
            return False
    return True


def num_gt(*a):
    for x, y in zip(a, a[1:]):
        if not (int(x) > int(y)):
            return False
    return True


def num_eq(*a):
    return all(int(a[0]) == int(x) for x in a[1:])


def cons(a, b):
    return [a] + _as_list(b)


def _as_list(x):
    if x is None or x == []:
        return []
    if isinstance(x, list):
        return x
    return [x]


def car(x):
    return x[0]


def cdr(x):
    if len(x) <= 1:
        return []
    return x[1:]


def lst(*a):
    return list(a)


def nullp(x):
    return x == [] or x is None


PRIMS = {
    '+': add, '-': sub, '*': mul,
    '=': num_eq, '<': num_lt, '>': num_gt,
    'car': car, 'cdr': cdr, 'cons': cons, 'list': lst,
    'eq?': lambda a, b: (isinstance(a, int) and isinstance(b, int) and a == b)
           or (isinstance(a, str) and isinstance(b, str) and a == b),
    'null?': nullp,
    'number?': lambda a: isinstance(a, int),
    'boolean?': lambda a: isinstance(a, bool),
    'pair?': lambda a: isinstance(a, list) and len(a) > 0,
    'symbol?': lambda a: isinstance(a, str) and a != '#t' and a != '#f',
    'not': lambda a: a is False,
}


# ---------------- procedures ----------------

class Closure:
    def __init__(self, params, body, env):
        self.params = params
        self.body = body
        self.env = env

    def __call__(self, args):
        local = Env(self.env)
        for p, a in zip(self.params, args):
            local.set(p, a)
        r = None
        for expr in self.body:
            r = evaluate(expr, local)
        return r


# ---------------- evaluator ----------------

def evaluate(expr, env):
    if isinstance(expr, int):
        return expr
    if isinstance(expr, str):
        if expr == '#t':
            return True
        if expr == '#f':
            return False
        if expr[0] == "'":
            return parse(expr[1:])
        # symbol
        if expr in PRIMS:
            return PRIMS[expr]
        return env.get(expr)
    # list form
    if not isinstance(expr, list) or len(expr) == 0:
        return expr
    head = expr[0]
    if head == 'quote':
        return expr[1]
    if head == 'if':
        cond = evaluate(expr[1], env)
        if cond is not False and cond != [] and cond is not None:
            return evaluate(expr[2], env)
        if len(expr) >= 4:
            return evaluate(expr[3], env)
        return None
    if head == 'define':
        name = expr[1]
        if isinstance(name, list):
            # (define (f p1 p2) body...) sugar
            fname, params = name[0], name[1:]
            env.set(fname, Closure(params, expr[2:], env))
            return None
        val = evaluate(expr[2], env) if len(expr) == 3 else Closure(expr[2], expr[3:], env)
        env.set(name, val)
        return None
    if head == 'lambda':
        return Closure(expr[1], expr[2:], env)
    if head == 'begin':
        r = None
        for e in expr[1:]:
            r = evaluate(e, env)
        return r
    if head == 'let':
        bindings = expr[1]
        body = expr[2:]
        local = Env(env)
        for b in bindings:
            local.set(b[0], evaluate(b[1], env))
        r = None
        for e in body:
            r = evaluate(e, local)
        return r
    if head == 'apply':
        proc = evaluate(expr[1], env)
        arglist = evaluate(expr[2], env)
        return apply_proc(proc, arglist)
    if head == 'eval':
        return evaluate(evaluate(expr[1], env), GLOBAL)
    # application
    proc = evaluate(expr[0], env)
    args = [evaluate(e, env) for e in expr[1:]]
    return apply_proc(proc, args)


def apply_proc(proc, args):
    args = _as_list(args)
    if isinstance(proc, Closure):
        return proc(args)
    if callable(proc):
        return proc(*args)
    raise TypeError("cannot apply " + repr(proc))


def parse(text):
    return Reader(text).read()


# ---------------- printer ----------------

def show(val):
    if val is None:
        return '<void>'
    if val is True:
        return '#t'
    if val is False:
        return '#f'
    if isinstance(val, int):
        return str(val)
    if isinstance(val, str):
        return val
    if isinstance(val, list):
        return '(' + ' '.join(show(x) for x in val) + ')'
    return '#<procedure>'


def main():
    text = sys.stdin.read()
    r = Reader(text)
    first = True
    while True:
        try:
            form = r.read()
        except Exception:
            break
        if form is None:
            break
        val = evaluate(form, GLOBAL)
        if form is not None and not (isinstance(form, list) and form and form[0] == 'define'):
            sys.stdout.write(show(val) + "\n")


if __name__ == '__main__':
    main()