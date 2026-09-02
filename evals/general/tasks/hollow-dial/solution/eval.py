#!/usr/bin/env python3
"""eval.py - a runnable interpreter for the 'Liz' Scheme-like language.

Liz is a small, precisely-specified Lisp dialect (see instruction.md).  The
evaluator is written so it can also run a *meta-circular* Liz program (a
self-host harness, e.g. /app/samples/self.lsp) that reimplements evaluation in
Liz itself and evaluates another target program through it -- i.e. one extra
nesting level.  Running the same target directly and via the harness must yield
byte-identical output; that property is what the verifier checks.

Usage:  python3 eval.py <program.lsp>
Output is written to stdout only by the `print` builtin; errors go to stderr
with a nonzero exit code.
"""
import sys

sys.setrecursionlimit(1000000)


class LizError(Exception):
    pass


class ParseError(Exception):
    pass


# --------------------------------------------------------------------------
# Pair / NIL value model (Lisp data live as Python objects distinct from the
# AST list objects the parser produces).
# --------------------------------------------------------------------------

class Pair(object):
    __slots__ = ('car', 'cdr')

    def __init__(self, car, cdr):
        self.car = car
        self.cdr = cdr


class Nil(object):
    __slots__ = ()
    _inst = None

    def __new__(cls):
        if cls._inst is None:
            cls._inst = super().__new__(cls)
        return cls._inst

    def __repr__(self):
        return "'()"


NIL = Nil()


def is_nil(v):
    return isinstance(v, Nil)


def is_pair(v):
    return isinstance(v, Pair)


def make_pair(a, b):
    return Pair(a, b)


def cons(a, b):
    return Pair(a, b)


def car(v):
    if not is_pair(v):
        raise LizError('car: not a pair')
    return v.car


def cdr(v):
    if not is_pair(v):
        raise LizError('cdr: not a pair')
    return v.cdr


def list_parts(v):
    out = []
    while is_pair(v):
        out.append(v.car)
        v = v.cdr
    if not is_nil(v):
        raise LizError('improper list where proper list required')
    return out


# --------------------------------------------------------------------------
# environment (resettable frames stack)
# --------------------------------------------------------------------------

class Env(object):
    __slots__ = ('map', 'parent')

    def __init__(self, parent=None):
        self.map = {}
        self.parent = parent

    def lookup(self, name):
        env = self
        while env is not None:
            if name in env.map:
                return env.map[name]
            env = env.parent
        return None

    def define(self, name, val):
        self.map[name] = val


BUILTIN_NAMES = ('+ - * quotient remainder = < > <= >= '
                 'cons car cdr null? pair? symbol? number? eq? not list print prim-eval')


class Closure(object):
    __slots__ = ('params', 'body', 'env')

    def __init__(self, params, body, env):
        self.params = params      # list of parameter name-> python str
        self.body = body          # list of AST forms
        self.env = env


# --------------------------------------------------------------------------
# writer (printed representation -- must be identical on both nesting paths)
# --------------------------------------------------------------------------

def write(v):
    if isinstance(v, bool):
        return '#t' if v else '#f'
    if isinstance(v, int):
        return str(v)
    if isinstance(v, str):
        return v
    if is_nil(v):
        return '()'
    if is_pair(v):
        parts = []
        cur = v
        while is_pair(cur):
            parts.append(write(cur.car))
            cur = cur.cdr
        if is_nil(cur):
            return '(' + ' '.join(parts) + ')'
        return '(' + ' '.join(parts) + ' . ' + write(cur) + ')'
    if isinstance(v, Closure):
        return '#<closure>'
    return '#<prim:' + str(v) + '>'


# --------------------------------------------------------------------------
# parser
# --------------------------------------------------------------------------

def tokenize(text):
    toks = []
    i = 0
    n = len(text)
    while i < n:
        c = text[i]
        if c == ';':
            while i < n and text[i] != '\n':
                i += 1
            continue
        if c in ' \t\r\n':
            i += 1
            continue
        if c in '()':
            toks.append(c)
            i += 1
            continue
        if c == "'":
            toks.append("'")
            i += 1
            continue
        j = i
        while j < n and text[j] not in '() \t\r\n;':
            j += 1
        toks.append(text[i:j])
        i = j
    return toks


def _atom(tok):
    if tok == '#t':
        return True
    if tok == '#f':
        return False
    if tok.isdigit():
        return int(tok)
    if abs_literal := (len(tok) > 1 and tok[0] == '-' and tok[1:].isdigit()):
        return -int(tok[1:])
    return tok   # symbol


def parse(text):
    toks = tokenize(text)
    pos = [0]

    def read():
        if pos[0] >= len(toks):
            raise ParseError('unexpected end of input')
        t = toks[pos[0]]
        if t == "'":
            pos[0] += 1
            inner = read()
            return ['quote', inner]
        if t == '(':
            pos[0] += 1
            lst = []
            while True:
                if pos[0] >= len(toks):
                    raise ParseError('unclosed "("')
                if toks[pos[0]] == ')':
                    pos[0] += 1
                    return lst
                lst.append(read())
        if t == ')':
            raise ParseError('unexpected ")"')
        pos[0] += 1
        return _atom(t)

    forms = []
    while pos[0] < len(toks):
        forms.append(read())
    return forms


# --------------------------------------------------------------------------
# AST -> value (used by `quote`)
# --------------------------------------------------------------------------

def ast_to_value(e):
    if isinstance(e, bool):
        return e
    if isinstance(e, int):
        return e
    if e == '':
        return e
    if isinstance(e, str):
        return e
    if len(e) == 0:
        return NIL
    return Pair(ast_to_value(e[0]), ast_to_value(e[1:]))


# --------------------------------------------------------------------------
# builtins
# --------------------------------------------------------------------------

def _num_eq(a, b):
    return isinstance(a, int) and not isinstance(a, bool) and \
           isinstance(b, int) and not isinstance(b, bool) and a == b


def call_builtin(name, args):
    if name == 'print':
        line = []
        for a in args:
            line.append(write(a))
        sys.stdout.write(' '.join(line) + '\n')
        return True
    if name == 'cons':
        return Pair(args[0], args[1])
    if name == 'car':
        return car(args[0])
    if name == 'cdr':
        return cdr(args[0])
    if name == 'null?':
        return is_nil(args[0])
    if name == 'pair?':
        return is_pair(args[0])
    if name == 'symbol?':
        return isinstance(args[0], str) and not isinstance(args[0], bool)
    if name == 'number?':
        return isinstance(args[0], int) and not isinstance(args[0], bool)
    if name in ('+', '-', '*', 'quotient', 'remainder', '=', '<', '>', '<=', '>='):
        a, b = args[0], args[1]
        if name == '+':
            return a + b
        if name == '-':
            return a - b
        if name == '*':
            return a * b
        if name == 'quotient':
            if b == 0:
                raise LizError('division by zero')
            return a // b
        if name == 'remainder':
            if b == 0:
                raise LizError('division by zero')
            return a % b
        if name == '=':
            return a == b
        if name == '<':
            return a < b
        if name == '>':
            return a > b
        if name == '<=':
            return a <= b
        if name == '>=':
            return a >= b
    if name == 'eq?':
        a, b = args[0], args[1]
        if _num_eq(a, b):
            return True
        if isinstance(a, str) and isinstance(b, str) and a == b:
            return True
        if isinstance(a, bool) and isinstance(b, bool) and a == b:
            return True
        if is_nil(a) and is_nil(b):
            return True
        return False
    if name == 'not':
        return True if args[0] is False else False
    if name == 'list':
        return list_to_pair(args)
    if name == 'prim-eval':
        pname = args[0]
        v = args[1]
        return call_builtin(pname, list_parts(v))
    raise LizError('unknown primitive: %s' % name)


def list_to_pair(items):
    out = NIL
    for x in reversed(items):
        out = Pair(x, out)
    return out


# --------------------------------------------------------------------------
# evaluator (direct path)
# --------------------------------------------------------------------------

def eval_expr(e, env):
    if isinstance(e, bool) or isinstance(e, int):
        return e
    if isinstance(e, str):
        v = env.lookup(e)
        if v is not None:
            return v
        return e      # unbound symbol denotes itself (matches meta-circular path)
    # compound (Python list AST)
    if len(e) == 0:
        raise LizError('cannot evaluate the empty list')
    head = e[0]
    if head == 'quote':
        return ast_to_value(e[1])
    if head == 'if':
        c = eval_expr(e[1], env)
        if c is False:
            return eval_expr(e[3], env)
        return eval_expr(e[2], env)
    if head == 'define':
        name_or_sig = e[1]
        if isinstance(name_or_sig, list):
            # shorthand: (define (name p1 p2 ...) body...)
            name = name_or_sig[0]
            params = [str(p) for p in name_or_sig[1:]]
            body = list(e[2:])
            val = Closure(params, body, env)
        else:
            name = name_or_sig
            val = eval_expr(e[2], env)
        env.define(name, val)
        return val
    if head == 'lambda':
        return Closure(list(e[1]), list(e[2:]), env)
    if head == 'begin':
        r = False
        for sub in e[1:]:
            r = eval_expr(sub, env)
        return r
    proc = eval_expr(head, env)
    args = [eval_expr(a, env) for a in e[1:]]
    return apply_proc(proc, args)


def apply_proc(proc, args):
    if isinstance(proc, Closure):
        env = Env(proc.env)
        for p, a in zip(proc.params, args):
            env.define(p, a)
        r = False
        for body in proc.body:
            r = eval_expr(body, env)
        return r
    if isinstance(proc, str):
        return call_builtin(proc, args)
    raise LizError('bad procedure value')


def run_file(path):
    with open(path) as f:
        text = f.read()
    forms = parse(text)
    env = Env()
    for form in forms:
        eval_expr(form, env)


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.stderr.write('usage: eval.py <program.lsp>\n')
        sys.exit(2)
    try:
        run_file(sys.argv[1])
    except LizError as ex:
        sys.stderr.write('error: %s\n' % ex)
        sys.exit(1)
    except RecursionError:
        sys.stderr.write('error: recursion limit exceeded\n')
        sys.exit(1)
    except ParseError as ex:
        sys.stderr.write('error: %s\n' % ex)
        sys.exit(1)
    except TypeError as ex:
        sys.stderr.write('error: evaluation type error: %s\n' % ex)
        sys.exit(1)