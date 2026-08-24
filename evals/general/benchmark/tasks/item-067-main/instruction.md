# Item-067 (medium) — extend a metacircular Scheme interpreter

`/app/interpreter.py` is a small **meta-circular** Scheme interpreter (it
implements `eval`/`apply` in the style of SICP §6.1). It already supports a
core subset:

- **special forms**: `quote`, `if`, `begin`, `define`, `lambda`, `let`,
  `set!`,
- **primitives**: arithmetic/comparison, `not`, `cons`/`car`/`cdr`, `list`,
  `null?`, `pair?`, `length`, `nth`, `append`, `map`, `filter`, `foldl`.

Inside `eval_()` there is a clearly marked `# === EXTENSION POINT ===` where
**new special forms** are dispatched (a *special form* is a list whose first
element is an unevaluated symbol). Your job is to extend the interpreter at
that point with three new special forms, doing it **incrementally** and using
**small programs as regression tests** so existing semantics stay intact.

## The three forms to add (exact semantics)

The interpreter's truth model is: **only `#f` (Python `False`) is false;
everything else is true.** Match that exactly.

1. **`cond`** — multi-branch:
   ```
   (cond (<test1> <expr1>) (<test2> <expr2>) ... [(else <expr>)] )
   ```
   Evaluate `<test_i>` in order; for the first one that is true, evaluate and
   return the corresponding `<expr_i>` (with `<expr_i>` the following element).
   Never evaluate a branch after the first true one. If no test is true and an
   `(else <expr>)  clause is present, evaluate and return it. If no test is
   true and there is no `else`, return the empty list `()`.

2. **`and`** — `(and <e1> <e2> ... )`. Evaluate terms left to right,
   **short-circuiting**: the moment a term is false (`#f`), stop and return
   that false value without evaluating the remaining terms. If all terms are
   true, return the **last** term's value. If there are no terms, return `#t`.

3. **`or`** — `(or <e1> <e2> ... )`. Evaluate terms left to right; return the
   **first** true value immediately (evaluating no further terms). If every
   term is false, return `#f`. If there are no terms, return `#f`.

Base these on how `eval_`/`apply`/`Env` already work, and take care that
`and`/`or` **are special forms** (their argument expressions are *not* all
evaluated — they short-circuit). Do not perturb the existing forms.

## Deliverable

Extend `/app/interpreter.py` (keep the filename and CLI). The grader will run
`python3 /app/interpreter.py` with stdin holding a Scheme program and compare
the printed result line to an expected value.

## Verifier cases (so you can self-test)

The grader compiles specific programs through `/app/interpreter.py` and
asserts exact printed lines. Representatively:

| program (via stdin)                       | expected line |
|-------------------------------------------|---------------|
| `(cond ((< 2 1) 5) ((< 1 2) 7))`          | `7`           |
| `(cond (#f 1) (else 9))`                 | `9`           |
| `(cond (#f 1) (#f 2))`                   | `()`          |
| `(and #t (> 3 2))`                       | `#t`          |
| `(and #t (< 1 0) 5)`                     | `#f`          |
| `(or #f #f)`                             | `#f`          |
| `(or #f 5 #t)`                           | `5`           |
| `(if (> 3 2) 100 200)`                   | `100`         |
| `(let ((x 5)) (begin (define (f a) (* a 2)) (f x)))` | `10` |

Booleans print as `#t`/`#f`; integers as `7` etc. Match those exactly. The
verifier also re-checks that `if`, `recursion`, `define`, `begin`, `let`,
`lambda`, `quote` still behave as before (no regressions).