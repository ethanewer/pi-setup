# Metacircular interpreter

Build a **metacircular interpreter**: an evaluator for a tiny LISP subset, written in Python, where the evaluator and the language it evaluates share the same pair-based data representation (`car`/`cdr`/`cons` cells).

Environment: `/app/pairs.py` already defines the data representation:

```python
def cons(a, b):  return {"car": a, "cdr": b}
def car(p):      return p["car"]
def cdr(p):      return p["cdr"]
NIL = None

def is_nil(x):   return x is None
def is_atom(x):  return not isinstance(x, dict)   # number or symbol
```

Write `/app/eval_expr.py` that implements `eval_lisp(expr, env=None)` handling at least:

- `(["quote", X])` → evaluate to `X` itself (quoted data, no deeper evaluation).
- `(["car", E])`, `(["cdr", E])`, `(["cons", E1, E2])` → apply the corresponding primitive to the values of their arguments.
- anything else → first evaluate each element, then take the head's value as a function and apply it to the remaining evaluated argument values (SICP-style metacircular reduce).

Then evaluate this expression and print the resulting Python list to stdout (`print(result)`):

```
(cons (car (quote (5 9 13))) (cdr (quote (8 -17 3.5))))
```

Trace: `(car '(5 9 13))` → `5`; `(cdr '(8 -17 3.5))` → `(-17 3.5)`; `(cons 5 '(-17 3.5))` → the list `(5 -17 3.5)`.

Run `python3 /app/eval_expr.py` and write the result to `/app/result.json`:

```json
[5, -17, 3.5]
```

The numbers are `5` (int), `-17` (int), `3.5` (float).