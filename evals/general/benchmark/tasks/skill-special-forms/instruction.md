# Lisp special forms: trace a recursive `define`

`/app/example.lisp` contains a tiny Lisp-style program that uses the **special
forms** `define`, `if`, `=`, `*`, and `-`:

```lisp
(define (f n)
  (if (= n 0)
      1
      (* n (f (- n 1)))))
(f 5)
```

Read the program and determine, by hand (no Lisp interpreter is needed), the
single integer that evaluating the final expression `(f 5)` returns.

Special-form semantics you need (Lisp / Scheme convention):

- `(= a b)` tests whether `a` and `b` are equal; it is true here only for `= n 0`.
- `(if cond then else)` evaluates `cond`; if truthy it returns the value of
  `then`, otherwise the value of `else`.
- `(- n 1)` subtracts.
- `(* n x)` multiplies.
- `define` binds the name `f` to the (anonymous) function; applying `f` calls
  it with the given argument, substituting that value for `n` throughout the
  body.

So `(f n)` = `1` if `n = 0`, otherwise `(* n (f (- n 1)))`. Trace the recursion.

Write **only** that integer (a base-10 whole number, no quotes, no trailing
text) to `/app/answer.txt`.