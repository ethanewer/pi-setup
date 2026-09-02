#!/bin/bash
set -euo pipefail
cat > /app/eval_expr.py <<'EOF'
import sys, json
sys.path.insert(0, '/app')
from pairs import cons, car, cdr, NIL

def parse(s):
    toks = s.replace('(', ' ( ').replace(')', ' ) ').split()
    def rd(i):
        if toks[i] == '(':
            lst = []
            i += 1
            while toks[i] != ')':
                v, i = rd(i)
                lst.append(v)
            return lst, i + 1
        t = toks[i]
        if t.lstrip('-').replace('.', '', 1).isdigit():
            return float(t) if '.' in t else int(t), i + 1
        return t, i + 1
    return rd(0)[0]

def to_lisp(obj):
    if obj is NIL:
        return []
    if isinstance(obj, dict):
        rest = to_lisp(cdr(obj))
        return [to_lisp(car(obj))] + rest if isinstance(rest, list) else [to_lisp(car(obj)), rest]
    return obj

def from_lisp(lst):
    if lst is None or lst == []:
        return NIL
    return cons(lst[0], from_lisp(lst[1:]))

def eval_lisp(expr):
    if isinstance(expr, (int, float)):
        return expr
    op = expr[0]
    if op == 'quote':
        return from_lisp(expr[1])
    evald = [eval_lisp(e) for e in expr[1:]]
    if op == 'car':
        return car(evald[0])
    if op == 'cdr':
        return cdr(evald[0])
    if op == 'cons':
        return cons(evald[0], evald[1])
    raise ValueError(op)

expr = parse("(cons (car (quote (5 9 13))) (cdr (quote (8 -17 3.5))))")
res = eval_lisp(expr)
out = to_lisp(res)
print(out)
json.dump(out, open('/app/result.json', 'w'))
EOF
python3 /app/eval_expr.py