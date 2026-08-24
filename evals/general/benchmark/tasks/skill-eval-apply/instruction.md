# EV (a tiny Lisp-like language)

`/app/prog.lisp` contains a program in a small Lisp-like language called EV. The
entire grammar is defined here and is the ONLY language feature set available.

## EV grammar

- `<int>` — a decimal integer (possibly negative).
- `(<op> <expr> <expr>)` — arithmetic application, where `<op>` is one of
  `add`, `sub`, `mul`, `div`. `div` is integer division truncating toward zero.
- `(if <cond> <then> <else>)` — conditional; a condition is an integer and is
  truthy iff non-zero (the result of evaluating a `cond` is always an int).
- `(define (<name> <params...>) <body>)` — define a user function.
- `(<name> <args...>)` — apply a function (built-in or user-defined) to its
  fully-evaluated arguments.

## Semantics (the eval/apply model)

Evaluation follows the classic **eval/apply** interpreter structure:

- `evaluate(expr, env)`: atoms evaluate to themselves (ints) or resolve in the
  environment (the primitives `add`, `sub`, `mul`, `div` and any user functions).
  For a list form, dispatch on the head: special forms `if`, `lambda`, and
  `define` are handled directly in `eval` (their operands are not pre-evaluated);
  anything else is a normal **application**: evaluate the operator expression,
  evaluate each argument expression, then call `apply`.
- `apply(fn, args)`: invokes a function on its evaluated argument values. For a
  user function this binds the parameter names to the argument values in a new
  child environment (that inherits the caller's environment) and returns
  `eval(body, child_env)`.

The program may contain more than one top-level form; only the **last** one's
value is the program result.

## Your task

Write a Python 3 script `/app/interp.py` that:

1. reads `/app/prog.lisp`,
2. tokenizes and parses the whole program,
3. evaluates the program under the eval/apply model above (evaluating every
   top-level form in order, keeping the last result),
4. writes `/app/result.json` containing exactly `{"value": <last result int>}`.

Run `/app/interp.py` so that `/app/result.json` exists with the correct value.
The file `/app/prog.lisp` contains:

```
(define (square x) (mul x x))
(square 7)
```

so the result must be `49`. The verifier parses the same EV grammar from
`/app/prog.lisp` independently and checks `/app/result.json`.