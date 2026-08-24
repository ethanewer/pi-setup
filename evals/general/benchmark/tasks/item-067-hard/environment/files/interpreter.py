"""Metacircular-style Scheme interpreter (subset) written in Python.

The evaluator is modeled on the classic meta-circular Scheme (eval/apply):
  - eval_() examines the shape of an expression and either handles a special
    form directly or falls through to application.
  - apply() invokes a procedure (a builtin fn or a user Proc) on evaluated
    arguments.
Environments are lexical frames chained through Env.parent.
"""

import functools

class Sym:
    __slots__ = ('name',)
    def __init__(self, name): self.name = name
    def __repr__(self): return "Sym(%r)" % self.name
    def __eq__(self, o): return isinstance(o, Sym) and o.name == self.name
    def __hash__(self): return hash(('Sym', self.name))

class Str:
    __slots__ = ('val',)
    def __init__(self, val): self.val = val
    def __repr__(self): return "Str(%r)" % self.val

class Proc:
    __slots__ = ('params', 'body', 'env', 'name')
    def __init__(self, params, body, env, name=None):
        self.params = params; self.body = body; self.env = env; self.name = name

NIL = []

def scheme_str(x):
    if x is False: return '#f'
    if x is True: return '#t'
    if x is None or x == NIL: return '()'
    if isinstance(x, (int, float)): return str(x)
    if isinstance(x, Str): return x.val
    if isinstance(x, Sym): return x.name
    if isinstance(x, list):
        return '(' + ' '.join(scheme_str(e) for e in x) + ')'
    return str(x)

# ---------------- lexer / parser ----------------
class Reader:
    def __init__(self, toks): self.toks = toks; self.i = 0
    def peek(self):
        return self.toks[self.i] if self.i < len(self.toks) else None
    def pop(self):
        t = self.toks[self.i]; self.i += 1; return t
    def done(self): return self.i >= len(self.toks)

def tokenize(src):
    toks = []; i = 0; n = len(src)
    while i < n:
        c = src[i]
        if c.isspace(): i += 1; continue
        if c in '()': toks.append(c); i += 1; continue
        if c == ';':
            j = src.find('\n', i); i = n if j < 0 else j + 1; continue
        if c == '"':
            j = i + 1; buf = []
            while j < n:
                if src[j] == '\\' and j + 1 < n: buf.append(src[j + 1]); j += 2
                elif src[j] == '"': j += 1; break
                else: buf.append(src[j]); j += 1
            toks.append('"' + ''.join(buf) + '"'); i = j; continue
        start = i
        while i < n and not src[i].isspace() and src[i] not in '()': i += 1
        toks.append(src[start:i])
    return toks

def atom(tok):
    if tok in ('#t', '#true'): return True
    if tok in ('#f', '#false'): return False
    if tok == 'nil': return NIL
    if tok.startswith('"') and tok.endswith('"'): return Str(tok[1:-1])
    t = tok[1:] if tok.startswith('-') else tok
    if t.isdigit(): return int(tok)
    if len(tok) > 0 and tok.replace('.', '').isdigit() and tok.count('.') == 1:
        return float(tok)
    return Sym(tok)

def read_expr(r):
    t = r.peek()
    if t == '(':
        r.pop(); lst = []
        while r.peek() != ')':
            lst.append(read_expr(r))
        r.pop(); return lst
    r.pop()
    return atom(t)

def parse(src):
    r = Reader(tokenize(src)); out = []
    while not r.done():
        out.append(read_expr(r))
    return out

# ---------------- environments ----------------
class Env:
    def __init__(self, parent=None):
        self.bindings = {}; self.parent = parent
    def set(self, n, v): self.bindings[n] = v
    def find(self, n):
        e = self
        while e is not None:
            if n in e.bindings: return e
            e = e.parent
        return None
    def get(self, n):
        e = self.find(n)
        if e is None: raise Exception("unbound symbol: %s" % n)
        return e.bindings[n]
    def mutate(self, n, v):
        e = self.find(n)
        if e is None: raise Exception("set!: unbound symbol %s" % n)
        e.bindings[n] = v

# ---------------- truthiness: only #f is false ----------------
def is_true(x):
    return x is not False

def asnum(x):
    return x if isinstance(x, (int, float)) else 0

def tovalue(x):
    if isinstance(x, Str): return x.val
    if isinstance(x, Sym): return x.name
    return x

# ---------------- primitives ----------------
def make_primitives():
    return {
        '+':    lambda *a: sum(asnum(v) for v in a),
        '*':    lambda *a: functools.reduce(lambda x, y: x * y, [asnum(v) for v in a], 1),
        '-':    lambda a, *r: -asnum(a) if not r else asnum(a) - sum(asnum(v) for v in r),
        '/':    lambda a, *r: 1.0 / asnum(a) if not r else asnum(a) / asnum(r[0]),
        'min':  lambda *a: min(asnum(v) for v in a),
        'max':  lambda *a: max(asnum(v) for v in a),
        'abs':  lambda a: abs(asnum(a)),
        'mod':  lambda a, b: asnum(a) % asnum(b),
        'quotient': lambda a, b: asnum(a) // asnum(b) if b else 0,
        '=':    lambda a, b: asnum(a) == asnum(b),
        '<':    lambda a, b: asnum(a) < asnum(b),
        '>':    lambda a, b: asnum(a) > asnum(b),
        '<=':   lambda a, b: asnum(a) <= asnum(b),
        '>=':   lambda a, b: asnum(a) >= asnum(b),
        'not':  lambda a: not is_true(a),
        'cons': lambda a, b: [a] + (b if isinstance(b, list) else [b]),
        'car':  lambda a: a[0],
        'cdr':  lambda a: a[1:],
        'list': lambda *a: list(a),
        'null?': lambda a: a == NIL,
        'pair?': lambda a: isinstance(a, list) and len(a) >= 2,
        'length': lambda a: len(a) if isinstance(a, list) else 0,
        'nth':  lambda a, i: a[i],
        'append': lambda a, b: a + b,
        'map':  lambda f, l: [apply(f, [e]) for e in l],
        'filter': lambda f, l: [e for e in l if is_true(apply(f, [e]))],
        'foldl': lambda f, init, l: functools.reduce(
            lambda acc, e: apply(f, [acc, e]), l, init),
    }

def make_global_env():
    env = Env()
    for k, v in make_primitives().items():
        env.set(k, v)
    return env

# ---------------- apply ----------------
def apply(proc, args):
    if isinstance(proc, Proc):
        env = Env(parent=proc.env)
        for p, a in zip(proc.params, args):
            env.set(p.name, a)
        result = NIL
        for body in proc.body:
            result = eval_(body, env)
        return result
    if callable(proc):
        return proc(*args)
    raise Exception("cannot apply: %r" % (proc,))

# ---------------- eval ----------------
def eval_(expr, env):
    # self-evaluating
    if isinstance(expr, (bool, int, float, Str)):
        return expr
    # symbol -> lookup from env
    if isinstance(expr, Sym):
        if expr is True or expr is False:
            return expr
        return env.get(expr.name)
    # lists -> special form or application
    if isinstance(expr, list):
        if not expr:
            return NIL
        op = expr[0]
        opn = op.name if isinstance(op, Sym) else None

        if opn == 'quote':
            return datum(expr[1])
        if opn == 'if':
            test = eval_(expr[1], env)
            if len(expr) > 3:
                return eval_(expr[2], env) if is_true(test) else eval_(expr[3], env)
            return eval_(expr[2], env) if is_true(test) else NIL
        if opn == 'define':
            target = expr[1]
            if isinstance(target, list):
                name = target[0]
                params = target[1:]
                env.set(name.name, Proc(list(params), expr[2:], Env(parent=env), name=name.name))
            else:
                env.set(target.name, eval_(expr[2], env))
            return NIL
        if opn == 'lambda':
            return Proc(expr[1], expr[2:], env)
        if opn == 'begin':
            result = NIL
            for e in expr[1:]:
                result = eval_(e, env)
            return result
        if opn == 'set!':
            env.mutate(expr[1].name, eval_(expr[2], env))
            return NIL
        if opn == 'let':
            bindings = expr[1]
            new = Env(parent=env)
            vals = {}
            for b in bindings:
                vals[b[0].name] = eval_(b[1], env)
            for k, v in vals.items():
                new.set(k, v)
            result = NIL
            for e in expr[2:]:
                result = eval_(e, new)
            return result
        # === EXTENSION POINT ===
        # New special forms must be dispatched here, before application.
        # A special form is a list whose first element is a symbol; handle it
        # by testing opn == '...' and returning the evaluated value.

        # application
        fn = eval_(expr[0], env)
        args = [eval_(e, env) for e in expr[1:]]
        return apply(fn, args)
    return expr

def datum(e):
    if isinstance(e, Sym): return Sym(e.name)
    if isinstance(e, list): return [datum(x) for x in e]
    return e

def run(src):
    import io, sys
    env = make_global_env()
    buf = io.StringIO()
    old_out, old_err = sys.stdout, sys.stderr
    sys.stdout = buf
    sys.stderr = buf
    try:
        for expr in parse(src):
            try:
                v = eval_(expr, env)
                buf.write(scheme_str(v) + "\n")
            except Exception as ex:
                buf.write("ERROR: %s\n" % ex)
    finally:
        sys.stdout, sys.stderr = old_out, old_err
    return buf.getvalue()

if __name__ == '__main__':
    import sys
    sys.stdout.write(run(sys.stdin.read()) + "\n")
