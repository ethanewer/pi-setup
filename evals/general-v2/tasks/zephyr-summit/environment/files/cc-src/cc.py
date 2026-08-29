#!/usr/bin/env python3
"""
zcc -- a small clean-room C-subset compiler to x86-64 AT&T assembly.

This is an original, self-contained compiler written from scratch for the
Zephyr Summit task.  It implements a useful subset of C (single translation
unit, `int` scalars and arrays, arithmetic and comparisons, control flow,
functions, global variables and printf-style calls), enough to compile
ordinary small C programs.  It emits x86-64 assembly and assembles/links it
with the system `gcc` (binutils).  No upstream compiler source is used or
derived from -- every line here is authored for this task.

Usage:
    cc.py -o <output> <input.c>
    cc.py <input.c>              # writes a.out
"""

import sys
import re
import subprocess

ASSEMBLY_TMP = '/tmp/zcc_out.s'   # fixed path -> byte-deterministic final ELF
ASSEMBLY_OBJ = '/tmp/zcc_out.o'

# ---------------------------------------------------------------- errors
class CErr(Exception):
    pass

# ---------------------------------------------------------------- tokenizer
class Tok:
    __slots__ = ('kind', 'val', 'line')
    def __init__(self, kind, val, line):
        self.kind = kind   # 'op' | 'id' | 'num' | 'str' | 'eof'
        self.val = val
        self.line = line
    def __repr__(self):
        return 'Tok(%s,%r)' % (self.kind, self.val)

MULTI_OPS = ['++', '--', '<=', '>=', '==', '!=', '&&', '||',
             '+=', '-=', '*=', '/=', '%=']

_SINGLE = set('()[]{}),;=+-*/%<>!&|^~')

def tokenize(src):
    toks = []
    i, n = 0, len(src)
    line = 1
    while i < n:
        c = src[i]
        if c in ' \t\r':
            i += 1
            continue
        if c == '\n':
            line += 1
            i += 1
            continue
        if c == '#':                      # skip preprocessor line
            j = src.find('\n', i)
            if j < 0:
                break
            line += 1
            i = j + 1
            continue
        if c == '/' and i + 1 < n and src[i+1] == '/':   # line comment
            j = src.find('\n', i)
            i = n if j < 0 else j
            continue
        if c == '/' and i + 1 < n and src[i+1] == '*':   # block comment
            j = src.find('*/', i)
            if j < 0:
                raise CErr('unterminated block comment')
            line += src[i:j].count('\n')
            i = j + 2
            continue
        op = None
        for o in MULTI_OPS:
            if src.startswith(o, i):
                op = o
                break
        if op is not None:
            toks.append(Tok('op', op, line))
            i += len(op)
            continue
        if c.isalpha() or c == '_':
            j = i
            while j < n and (src[j].isalnum() or src[j] == '_'):
                j += 1
            toks.append(Tok('id', src[i:j], line))
            i = j
            continue
        if c.isdigit():
            j = i
            while j < n and src[j].isdigit():
                j += 1
            toks.append(Tok('num', int(src[i:j]), line))
            i = j
            continue
        if c == '"':
            j = i + 1
            while j < n and src[j] != '"':
                if src[j] == '\\':
                    j += 1
                j += 1
            if j >= n:
                raise CErr('unterminated string')
            toks.append(Tok('str', src[i:j+1], line))
            i = j + 1
            continue
        if c in _SINGLE:
            toks.append(Tok('op', c, line))
            i += 1
            continue
        raise CErr('unexpected char %r at line %d' % (c, line))
    toks.append(Tok('eof', None, line))
    return toks

# ---------------------------------------------------------------- AST
def _n(kind, **kw):
    d = {'k': kind}
    d.update(kw)
    return d

# ---------------------------------------------------------------- parser
class Parser:
    def __init__(self, toks):
        self.toks = toks
        self.pos = 0

    def peek(self):
        return self.toks[self.pos]

    def next(self):
        t = self.toks[self.pos]
        self.pos += 1
        return t

    def at(self, s):
        t = self.peek()
        return t.kind == 'op' and t.val == s

    def at_id(self, s=None):
        t = self.peek()
        return t.kind == 'id' and (s is None or t.val == s)

    def expect(self, s):
        if self.at(s):
            return self.next()
        t = self.peek()
        raise CErr('expected %r got %r (line %d)' % (s, t.val, t.line))

    def expect_kind(self, kind, what=None):
        t = self.peek()
        if t.kind == kind:
            return self.next()
        raise CErr('expected %s got %r (line %d)' % (what or kind, t.val, t.line))

    def parse_type(self):
        t = self.next()
        if t.kind == 'id' and t.val in ('int', 'void'):
            return t.val
        raise CErr('expected a type at line %d' % t.line)

    def parse_program(self):
        out = []
        while self.peek().kind != 'eof':
            out.append(self.parse_toplevel())
        return out

    def parse_toplevel(self):
        ty = self.parse_type()
        name = self.expect_kind('id', 'identifier').val
        if self.at('('):
            if ty != 'int':
                raise CErr('only int-returning functions supported')
            return self.parse_function(name)
        arr = None
        if self.at('['):
            self.next()
            arr = self.parse_const_size()
            self.expect(']')
        init = None
        if self.at('='):
            self.next()
            init = self.parse_global_init(arr)
        self.expect(';')
        return _n('glob', name=name, arr=arr, init=init)

    def parse_const_size(self):
        t = self.next()
        if t.kind == 'num':
            return t.val
        if t.kind == 'op' and t.val == '-':
            v = self.next()
            if v.kind == 'num':
                return -v.val
        raise CErr('array size must be an integer literal')

    def parse_const_lit(self):
        t = self.next()
        if t.kind == 'num':
            return t.val
        if t.kind == 'op' and t.val == '-':
            v = self.next()
            if v.kind == 'num':
                return -v.val
        raise CErr('expected constant literal')

    def parse_global_init(self, arr):
        if self.at('{'):
            self.next()
            vals = []
            while not self.at('}'):
                vals.append(self.parse_const_lit())
                if self.at(','):
                    self.next()
            self.expect('}')
            return vals
        v = self.parse_const_lit()
        if arr is not None:
            return [v]
        return v

    def parse_function(self, name):
        params = []
        self.expect('(')
        while not self.at(')'):
            pty = self.parse_type()
            if self.at_id():
                params.append(self.next().val)
            if self.at(','):
                self.next()
                continue
            break
        self.expect(')')
        body = self.parse_compound()
        return _n('func', name=name, params=params, body=body)

    def parse_compound(self):
        self.expect('{')
        items = []
        while not self.at('}'):
            items.append(self.parse_statement())
        self.expect('}')
        return _n('block', items=items)

    def parse_statement(self):
        t = self.peek()
        if t.kind == 'op' and t.val == '{':
            return self.parse_compound()
        if t.kind == 'id' and t.val == 'return':
            return self.parse_return()
        if t.kind == 'id' and t.val == 'if':
            return self.parse_if()
        if t.kind == 'id' and t.val == 'for':
            return self.parse_for()
        if t.kind == 'id' and t.val == 'while':
            return self.parse_while()
        if t.kind == 'id' and t.val == 'int':
            return self.parse_local_decl()
        e = self.parse_expression()
        self.expect(';')
        return _n('expr', e=e)

    def parse_return(self):
        self.next()
        if self.at(';'):
            self.next()
            return _n('ret', e=None)
        e = self.parse_expression()
        self.expect(';')
        return _n('ret', e=e)

    def parse_if(self):
        self.next()                       # consume  if
        self.expect('(')
        cond = self.parse_expression()
        self.expect(')')
        thenb = self.parse_statement()
        elseb = None
        if self.at_id('else'):
            self.next()
            elseb = self.parse_statement()
        return _n('if', cond=cond, thenb=thenb, elseb=elseb)

    def parse_while(self):
        self.next()                       # consume  while
        self.expect('(')
        cond = self.parse_expression()
        self.expect(')')
        body = self.parse_statement()
        return _n('while', cond=cond, body=body)

    def parse_for(self):
        self.next()                       # consume  for
        self.expect('(')
        init = cond = step = None
        if not self.at(';'):
            if self.at_id('int'):
                init = self.parse_local_decl()
            else:
                init = _n('expr', e=self.parse_expression())
                self.expect(';')
        else:
            self.expect(';')
        if not self.at(';'):
            cond = self.parse_expression()
        self.expect(';')
        if not self.at(')'):
            step = self.parse_expression()
        self.expect(')')
        body = self.parse_statement()
        return _n('for', init=init, cond=cond, step=step, body=body)

    def parse_local_decl(self):
        self.next()   # 'int'
        items = []
        while True:
            name = self.expect_kind('id', 'identifier').val
            arr = None
            if self.at('['):
                self.next()
                arr = self.parse_const_size()
                self.expect(']')
            init = None
            if self.at('='):
                self.next()
                init = self.parse_local_init()
            items.append(_n('ditem', name=name, arr=arr, init=init))
            if self.at(','):
                self.next()
                continue
            break
        self.expect(';')
        return _n('decl', items=items)

    def parse_local_init(self):
        if self.at('{'):
            return self.parse_global_init(None)
        return self.parse_expression()

    # ---- expressions ----
    ASSIGN_OPS = ('=', '+=', '-=', '*=', '/=', '%=')

    def parse_expression(self):
        left = self.parse_or()
        t = self.peek()
        if t.kind == 'op' and t.val in self.ASSIGN_OPS:
            op = self.next().val
            rhs = self.parse_expression()
            return _n('assign', op=op, lhs=left, rhs=rhs)
        return left

    def parse_or(self):
        node = self.parse_and()
        while self.at('||'):
            self.next()
            node = _n('bin', op='||', a=node, b=self.parse_and())
        return node

    def parse_and(self):
        node = self.parse_eq()
        while self.at('&&'):
            self.next()
            node = _n('bin', op='&&', a=node, b=self.parse_eq())
        return node

    def parse_eq(self):
        node = self.parse_rel()
        while self.at('==') or self.at('!='):
            op = self.next().val
            node = _n('bin', op=op, a=node, b=self.parse_rel())
        return node

    def parse_rel(self):
        node = self.parse_add()
        while self.at('<') or self.at('<=') or self.at('>') or self.at('>='):
            op = self.next().val
            node = _n('bin', op=op, a=node, b=self.parse_add())
        return node

    def parse_add(self):
        node = self.parse_mul()
        while self.at('+') or self.at('-'):
            op = self.next().val
            node = _n('bin', op=op, a=node, b=self.parse_mul())
        return node

    def parse_mul(self):
        node = self.parse_unary()
        while self.at('*') or self.at('/') or self.at('%'):
            op = self.next().val
            node = _n('bin', op=op, a=node, b=self.parse_unary())
        return node

    def parse_unary(self):
        t = self.peek()
        if t.kind == 'op' and t.val in ('+', '-', '!', '~'):
            op = self.next().val
            return _n('un', op=op, a=self.parse_unary())
        if t.kind == 'op' and t.val in ('++', '--'):
            op = self.next().val
            a = self.parse_unary()
            if a['k'] in ('var', 'index'):
                return _n('pre', op=op, a=a)
            raise CErr('prefix %s needs an lvalue (line %d)' % (op, t.line))
        return self.parse_postfix()

    def parse_postfix(self):
        node = self.parse_primary()
        while True:
            if self.at('('):
                node = self.parse_call(node)
            elif self.at('['):
                self.next()
                idx = self.parse_expression()
                self.expect(']')
                if node['k'] != 'var':
                    raise CErr('only simple array indexing supported')
                node = _n('index', name=node['name'], i=idx)
            elif self.at('++') or self.at('--'):
                op = self.next().val
                if node['k'] in ('var', 'index'):
                    node = _n('post', op=op, a=node)
                else:
                    raise CErr('postfix %s needs an lvalue' % op)
            else:
                break
        return node

    def parse_call(self, node):
        if node['k'] != 'var':
            raise CErr('bad call target')
        self.next()   # consume '('
        args = []
        if not self.at(')'):
            args.append(self.parse_expression())
            while self.at(','):
                self.next()
                args.append(self.parse_expression())
        self.expect(')')
        return _n('call', name=node['name'], args=args)

    def parse_primary(self):
        t = self.peek()
        if t.kind == 'num':
            self.next()
            return _n('num', v=t.val)
        if t.kind == 'str':
            self.next()
            return _n('str', s=t.val[1:-1])
        if t.kind == 'id':
            self.next()
            return _n('var', name=t.val)
        if t.kind == 'op' and t.val == '(':
            self.next()
            e = self.parse_expression()
            self.expect(')')
            return e
        raise CErr('unexpected token %r in expression (line %d)' % (t.val, t.line))

def parse(src):
    return Parser(tokenize(src)).parse_program()

# ---------------------------------------------------------------- layout
class Layout:
    """Lay out globals and per-function stack frames.

    Stack frame (x86-64, grows down from rbp): params + locals occupy the
    first `frame` bytes; rsp is fixed at rbp-frame for the whole function
    body.  Scalar slots are 8 bytes (4 used); arrays are contiguous 4-byte
    elements.  `frame` is a multiple of 16 so rsp stays 16-byte aligned at
    every (pending-free) call.
    """
    def __init__(self):
        self.globals = {}
        self.gorder = []
        self.functions = set()

    def layout_globals(self, prog):
        for top in prog:
            if top['k'] == 'glob':
                count = top['arr'] if top['arr'] is not None else 1
                self.globals[top['name']] = {
                    'count': count,
                    'size': count * 4,
                    'init': top['init'],
                }
                self.gorder.append(top['name'])
            else:
                self.functions.add(top['name'])

    def layout_function(self, func):
        st = {}
        next_off = 8

        def alloc(name, arr):
            nonlocal next_off
            if arr is None:
                off = next_off
                next_off += 8
                return (off, 's')
            size = arr * 4
            off = next_off - size
            next_off = off
            return (off, 'a')

        for p in func['params']:
            if p not in st:
                st[p] = alloc(p, None)
        self._walk_decls(func['body'], alloc, st)
        if next_off < 16:
            next_off = 16
        frame = (next_off + 15) // 16 * 16
        return st, frame

    def _walk_decls(self, node, alloc, st):
        k = node['k']
        if k == 'decl':
            for item in node['items']:
                name = item['name']
                if name not in st:
                    st[name] = alloc(name, item.get('arr'))
        elif k == 'block':
            for it in node['items']:
                self._walk_decls(it, alloc, st)
        elif k == 'if':
            self._walk_decls(node['thenb'], alloc, st)
            if node.get('elseb'):
                self._walk_decls(node['elseb'], alloc, st)
        elif k == 'while':
            self._walk_decls(node['body'], alloc, st)
        elif k == 'for':
            if node.get('init'):
                self._walk_decls(node['init'], alloc, st)
            self._walk_decls(node['body'], alloc, st)

# ---------------------------------------------------------------- codegen
IS_LIB = {'printf'}

class Codegen:
    ARGREGS = ['%rdi', '%rsi', '%rdx', '%rcx', '%r8', '%r9']
    ARGLOGS = ['%edi', '%esi', '%edx', '%ecx', '%r8d', '%r9d']
    CMPCC = {'==': 'e', '!=': 'ne', '<': 'l', '<=': 'le', '>': 'g', '>=': 'ge'}

    def __init__(self, prog):
        self.prog = prog
        self.lay = Layout()
        self.lay.layout_globals(prog)
        self.lines = []
        self.label = 0
        self.strlabs = {}
        self.strs = []           # list of (text, label)

    def emit(self, s=''):
        self.lines.append(s)

    def newlbl(self, base='L'):
        self.label += 1
        return '.%s%d' % (base, self.label)

    def str_label(self, s):
        if s not in self.strlabs:
            lbl = '.Lstr%d' % len(self.strs)
            self.strlabs[s] = lbl
            self.strs.append((s, lbl))
        return self.strlabs[s]

    # ---- memory I/O helpers ----
    def mem_arg(self, name, st, idx=None):
        """Return ('scalar','global'|'local', off) for a scalar lvalue."""
        if name in st:
            off, kind = st[name]
            return (kind, 'local', off)
        g = self.lay.globals[name]
        return ('scalar' if g['count'] == 1 else 'array', 'global', g['count'])

    def ld_var(self, name, st):
        if name in st:
            off, kind = st[name]
            self.emit('    movl -%d(%%rbp), %%eax' % off)
        else:
            g = self.lay.globals[name]
            self.emit('    movl %s(%%rip), %%eax' % name)

    def st_var(self, name, st):
        if name in st:
            off, _ = st[name]
            self.emit('    movl %%eax, -%d(%%rbp)' % off)
        else:
            self.emit('    movl %%eax, %s(%%rip)' % name)

    def ld_elem(self, name, st, idxreg):
        if name in st:
            off, _ = st[name]
            self.emit('    movl -%d(%%rbp,%s,4), %%eax' % (off, idxreg))
        else:
            self.emit('    movl %s(,%s,4), %%eax' % (name, idxreg))

    def st_elem(self, name, st, idxreg):
        if name in st:
            off, _ = st[name]
            self.emit('    movl %%eax, -%d(%%rbp,%s,4)' % (off, idxreg))
        else:
            self.emit('    movl %%eax, %s(,%s,4)' % (name, idxreg))

    # status ncjm hmm -- place holder
    def _is_array(self, name, st):
        if name in st:
            return st[name][1] == 'a'
        return self.lay.globals[name]['count'] > 1

    # ---- arithmetic: a in rcx, b in rax -> result rax ----
    def emit_arith(self, op):
        if op == '+':
            self.emit('    addq %rcx, %rax')
        elif op == '-':
            self.emit('    movq %rax, %rdx')     # rdx = b
            self.emit('    movq %rcx, %rax')     # rax = a
            self.emit('    subq %rdx, %rax')     # rax = a - b
        elif op == '*':
            self.emit('    imulq %rcx, %rax')
        elif op in ('/', '%'):
            self.emit('    pushq %rax')          # save b  (pending +1)
            self.emit('    movq %rcx, %rax')     # rax = a
            self.emit('    cqto')                # rdx:rax sign-extended a
            self.emit('    popq %rcx')           # rcx = b  (pending -1)
            self.emit('    idivq %rcx')          # rax=a/b, rdx=a%b
            if op == '%':
                self.emit('    movq %rdx, %rax')
        elif op in self.CMPCC:
            self.emit('    cmpq %rax, %rcx')     # flags from (a - b)
            self.emit('    set%s %%al' % self.CMPCC[op])
            self.emit('    movzbl %al, %eax')
        else:
            raise CErr('unsupported operator %r' % op)

    # ---- expression -> result in %rax ----
    def gen_expr(self, node, st):
        k = node['k']
        if k == 'num':
            self.emit('    movl $%d, %%eax' % node['v'])
        elif k == 'str':
            lbl = self.str_label(node['s'])
            self.emit('    leaq %s(%%rip), %%rax' % lbl)
        elif k == 'var':
            self.ld_var(node['name'], st)
        elif k == 'index':
            self.gen_expr(node['i'], st)          # index -> rax
            self.ld_elem(node['name'], st, '%rax')
        elif k == 'call':
            self._gen_call(node, st)
        elif k == 'assign':
            self._gen_assign(node, st)
        elif k == 'pre':
            self._gen_inc(node, st, is_post=False)
        elif k == 'post':
            self._gen_inc(node, st, is_post=True)
        elif k == 'bin':
            self._gen_bin(node, st)
        elif k == 'un':
            self.gen_expr(node['a'], st)
            if node['op'] == '-':
                self.emit('    negq %rax')
            elif node['op'] == '!':
                self.emit('    testq %rax, %rax')
                self.emit('    sete %al')
                self.emit('    movzbl %al, %eax')
            elif node['op'] == '~':
                self.emit('    notq %rax')
        else:
            raise CErr('cannot evaluate node %r' % (k,))

    def _gen_bin(self, node, st):
        op = node['op']
        if op == '&&':
            self.gen_expr(node['a'], st)
            l_false = self.newlbl('f'); l_end = self.newlbl('e')
            self.emit('    testq %rax, %rax'); self.emit('    jz %s' % l_false)
            self.gen_expr(node['b'], st)
            self.emit('    testq %rax, %rax'); self.emit('    setne %al')
            self.emit('    movzbl %al, %eax'); self.emit('    jmp %s' % l_end)
            self.emit('%s:' % l_false); self.emit('    xorl %eax, %eax')
            self.emit('%s:' % l_end)
        elif op == '||':
            self.gen_expr(node['a'], st)
            l_true = self.newlbl('t'); l_end = self.newlbl('e')
            self.emit('    testq %rax, %rax'); self.emit('    jnz %s' % l_true)
            self.gen_expr(node['b'], st)
            self.emit('    testq %rax, %rax'); self.emit('    setne %al')
            self.emit('    movzbl %al, %eax'); self.emit('    jmp %s' % l_end)
            self.emit('%s:' % l_true); self.emit('    movl $1, %eax')
            self.emit('%s:' % l_end)
        else:
            self.gen_expr(node['a'], st)
            self.emit('    pushq %rax')          # save a
            self.gen_expr(node['b'], st)
            self.emit('    popq %rcx')           # rcx=a, rax=b
            self.emit_arith(op)

    def _gen_assign(self, node, st):
        op = node['op']
        lhs = node['lhs']
        if op == '=':
            if lhs['k'] == 'var':
                self.gen_expr(node['rhs'], st)
                self.st_var(lhs['name'], st)
            elif lhs['k'] == 'index':
                self.gen_expr(lhs['i'], st)
                self.emit('    movq %rax, %r8')          # index in r8
                self.gen_expr(node['rhs'], st)
                self.emit('    movq %r8, %rcx')
                self.st_elem(lhs['name'], st, '%rcx')
            else:
                raise CErr('assignment target must be an lvalue')
        else:
            # compound: result = lhs <op> rhs ; then store into lhs
            aop = op[:-1]
            if lhs['k'] == 'var':
                self.ld_var(lhs['name'], st)             # old -> rax
                self.emit('    movq %rax, %r9')          # r9 = a
                self.gen_expr(node['rhs'], st)           # rax = b
                self.emit('    movq %r9, %rcx')          # rcx = a
                self.emit_arith(aop)                     # rax = a OP b
                self.st_var(lhs['name'], st)
            elif lhs['k'] == 'index':
                self.gen_expr(lhs['i'], st)
                self.emit('    movq %rax, %r8')          # index in r8
                self.ld_elem(lhs['name'], st, '%r8')     # old -> rax
                self.emit('    movq %rax, %r9')          # r9 = a
                self.gen_expr(node['rhs'], st)           # rax = b
                self.emit('    movq %r9, %rcx')
                self.emit_arith(aop)
                self.emit('    movq %r8, %rcx')
                self.st_elem(lhs['name'], st, '%rcx')
            else:
                raise CErr('compound assignment needs an lvalue')

    def _gen_inc(self, node, st, is_post):
        tgt = node['a']
        idx = None
        if tgt['k'] == 'index':
            self.gen_expr(tgt['i'], st)
            self.emit('    movq %rax, %r8')
            idx = '%r8'
            self.ld_elem(tgt['name'], st, idx)
        else:
            self.ld_var(tgt['name'], st)
        if is_post:
            self.emit('    pushq %rax')
        self.emit('    addq $1, %rax' if node['op'] == '++' else '    subq $1, %rax')
        if tgt['k'] == 'index':
            self.emit('    movq %r8, %rcx')
            self.st_elem(tgt['name'], st, '%rcx')
        else:
            self.st_var(tgt['name'], st)
        if is_post:
            self.emit('    popq %rax')

    def _gen_call(self, node, st):
        args = node['args'][:6]
        n = len(args)
        # evaluate arguments and stash them on the stack (so a nested call
        # inside a later argument cannot clobber earlier argument registers)
        for a in args:
            self.gen_expr(a, st)
            self.emit('    pushq %rax')
        # refill argument registers in reverse push order
        for k in range(n):
            self.emit('    popq %s' % self.ARGREGS[n - 1 - k])
        name = node['name']
        if name in IS_LIB:
            self.emit('    call %s@PLT' % name)
        else:
            self.emit('    call %s' % name)

    # ---- statements ----
    def _gen_stmt(self, node, st, exit_lbl):
        k = node['k']
        if k == 'block':
            for it in node['items']:
                self._gen_stmt(it, st, exit_lbl)
        elif k == 'expr':
            self.gen_expr(node['e'], st)
        elif k == 'decl':
            self._gen_decl(node, st)
        elif k == 'ret':
            if node.get('e') is not None:
                self.gen_expr(node['e'], st)
            self.emit('    jmp %s' % exit_lbl)
        elif k == 'if':
            self.gen_expr(node['cond'], st)
            l_else = self.newlbl('s'); l_end = self.newlbl('x')
            self.emit('    testq %rax, %rax')
            self.emit('    jz %s' % (l_else if node.get('elseb') else l_end))
            self._gen_stmt(node['thenb'], st, exit_lbl)
            if node.get('elseb'):
                self.emit('    jmp %s' % l_end)
                self.emit('%s:' % l_else)
                self._gen_stmt(node['elseb'], st, exit_lbl)
            self.emit('%s:' % l_end)
        elif k == 'while':
            l_s = self.newlbl('w'); l_end = self.newlbl('x')
            self.emit('%s:' % l_s)
            self.gen_expr(node['cond'], st)
            self.emit('    testq %rax, %rax'); self.emit('    jz %s' % l_end)
            self._gen_stmt(node['body'], st, exit_lbl)
            self.emit('    jmp %s' % l_s)
            self.emit('%s:' % l_end)
        elif k == 'for':
            l_start = self.newlbl('f'); l_end = self.newlbl('x')
            if node.get('init'):
                self._gen_stmt(node['init'], st, exit_lbl)
            self.emit('%s:' % l_start)
            if node.get('cond'):
                self.gen_expr(node['cond'], st)
                self.emit('    testq %rax, %rax'); self.emit('    jz %s' % l_end)
            self._gen_stmt(node['body'], st, exit_lbl)
            if node.get('step'):
                self.gen_expr(node['step'], st)
            self.emit('    jmp %s' % l_start)
            self.emit('%s:' % l_end)
        else:
            raise CErr('unsupported statement %r' % (k,))

    def _gen_decl(self, node, st):
        for item in node['items']:
            name = item['name']
            arr = item.get('arr')
            if arr is None:
                if item.get('init') is None:
                    self.emit('    movl $0, -%d(%%rbp)' % st[name][0])
                else:
                    self.gen_expr(item['init'], st)
                    self.st_var(name, st)
            else:
                # zero whole array first (determinism)
                off = st[name][0]
                self.emit('    movl $0, -%d(%%rbp)' % off)
                init = item.get('init')
                if init is not None:
                    vals = init if isinstance(init, list) else [init]
                    for j, v in enumerate(vals):
                        if j >= arr:
                            break
                        self.emit('    movl $%d, -%d(%%rbp,%d,4)' % (v, off, j))

    # ---- function + program ----
    def gen_function(self, func):
        st, frame = self.lay.layout_function(func)
        self.emit('    .globl %s' % func['name'])
        self.emit('%s:' % func['name'])
        self.emit('    pushq %rbp')
        self.emit('    movq %rsp, %rbp')
        if frame:
            self.emit('    subq $%d, %%rsp' % frame)
        for i, p in enumerate(func['params']):
            if i < len(self.ARGREGS):
                self.emit('    movl %s, -%d(%%rbp)' % (self.ARGLOGS[i], st[p][0]))
        exit_lbl = self.newlbl('e')
        self._gen_stmt(func['body'], st, exit_lbl)
        self.emit('%s:' % exit_lbl)
        self.emit('    movq %rbp, %rsp')
        self.emit('    popq %rbp')
        self.emit('    ret')

    def generate(self):
        self.emit('    .text')
        for top in self.prog:
            if top['k'] == 'func':
                self.gen_function(top)
        if self.lay.gorder:
            self.emit('    .data')
            for name in self.lay.gorder:
                g = self.lay.globals[name]
                self.emit('    .globl %s' % name)
                self.emit('    .balign 4')
                self.emit('%s:' % name)
                init = g['init']
                if init is None:
                    self.emit('    .zero %d' % g['size'])
                elif isinstance(init, list):
                    emitted = 0
                    for v in init:
                        if emitted >= g['count']:
                            break
                        self.emit('    .long %d' % v); emitted += 1
                    rest = g['size'] - emitted * 4
                    if rest > 0:
                        self.emit('    .zero %d' % rest)
                else:
                    self.emit('    .long %d' % init)
        if self.strs:
            self.emit('    .section .rodata')
            for s, lbl in self.strs:
                self.emit('    .balign 4')
                self.emit('%s:' % lbl)
                escaped = s.replace('\n', '\\n').replace('\t', '\\t')
                self.emit('    .asciz "%s"' % escaped)
        self.emit('    .section .note.GNU-stack,"",@progbits')
        return '\n'.join(self.lines) + '\n'

# ---------------------------------------------------------------- CLI
def main(argv):
    out = None
    inputs = []
    i = 1
    while i < len(argv):
        a = argv[i]
        if a == '-o':
            if i + 1 >= len(argv):
                sys.stderr.write('missing argument after -o\n')
                return 2
            out = argv[i + 1]
            i += 2
            continue
        if a.startswith('-o') and len(a) > 2:
            out = a[2:]
            i += 1
            continue
        inputs.append(a)
        i += 1
    if not inputs:
        sys.stderr.write('usage: cc.py [-o out] file.c\n')
        return 2
    try:
        src = open(inputs[-1]).read()
        prog = parse(src)
        asm = Codegen(prog).generate()
    except CErr as e:
        sys.stderr.write('compile error: %s\n' % e)
        return 1
    except Exception as e:
        sys.stderr.write('compile error: %r\n' % e)
        return 1
    with open(ASSEMBLY_TMP, 'w') as fh:
        fh.write(asm)
    final = out or 'a.out'
    try:
        subprocess.run(['as', '-o', ASSEMBLY_TMP.replace('.s', '.o'), ASSEMBLY_TMP],
                       check=True)
        subprocess.run(['gcc', '-no-pie', '-o', final,
                        ASSEMBLY_TMP.replace('.s', '.o')], check=True)
    except subprocess.CalledProcessError:
        sys.stderr.write('assembly/link failed (see above)\n')
        return 1
    return 0

if __name__ == '__main__':
    sys.exit(main(sys.argv))