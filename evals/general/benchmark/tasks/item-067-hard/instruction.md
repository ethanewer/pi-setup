# Item-067 (hard) — deep extension of a metacircular Scheme interpreter

`/app/interpreter.py` is a meta-circular Scheme interpreter (SICP-style
`eval`/`apply`, lexical `Env` chains). It already supports `quote`, `if`,
`begin`, `define`, `lambda`, `let`, `set!` and a primitive library
(`cons/car/cdr/list/null?/pair?/length/nth/append/map/filter/foldl`,
arithmetic/comparison, `not`).

Truth model: **only `#f` is false; everything else is true.**

Your job: add **five** new special forms at the `# === EXTENSION POINT ===`
marker in `eval_()`. Derive semantics from how the existing forms are
implemented, build them incrementally, and regression-test each with small
programs before moving on.

## Forms to add (exact semantics)

1. **`let*`** — sequential bindings: `(let* ((x 1) (y (+ x 1))) y)` => `2`.
   Each binding sees the bindings before it (unlike `let`).

2. **`when`** — `(when <test> <e1> <e2> ...)`: if `<test>` is true, evaluate
   all body expressions in order and return the last; otherwise return `()`.

3. **`unless`** — `(unless <test> <e1> ...)`: the mirror of `when`; evaluates
   the body only when `<test>` is false, else returns `()`.

4. **`cond`** — `(cond (<t1> <e1>) (<t2> <e2>) ... [(else <e>)])` as in R5RS:
   first true test's expression is returned; `(else <e>)` is the fallback;
   if no test is true and no `else`, return `()`. Short-circuits: later
   clauses are never evaluated.

5. **`case`** — `(case <key> ((<d1> <d2> ...) <e1>) ((<d3>) <e2>) ... [(else <e>)])`:
   evaluate `<key>` once; compare it (by Scheme equality of symbols/numbers)
   against each clause's datum list (data are NOT evaluated); evaluate and
   return the matching clause's expression; `else` is the fallback; if no
   clause matches and no `else`, return `()`.

All five must be **special forms** — argument expressions must not be
evaluated eagerly, and scoping must use the lexical `Env` machinery already
present (do not flatten environments or reimplement the evaluator).

## Constraints

- Keep the filename and CLI: `python3 /app/interpreter.py` reads a Scheme
  program from stdin and prints the result of each top-level expression, one
  per line.
- Do not change existing semantics; all previously working programs must
  produce identical output.

## Self-test examples

| program | expected line |
|---|---|
| `(let* ((x 2) (y (* x 3))) (+ x y))` | `8` |
| `(when (> 3 1) 10 20)` | `20` |
| `(when (< 3 1) 10)` | `()` |
| `(unless (< 3 1) 42)` | `42` |
| `(cond ((< 2 1) 5) ((< 1 2) 7))` | `7` |
| `(cond (#f 1) (else 9))` | `9` |
| `(case 2 ((1) 10) ((2 3) 20) (else 30))` | `20` |
| `(case 9 ((1) 10) ((2) 20))` | `()` |
| `(begin (define (f n) (let* ((a n) (b (* a 2))) (cond ((> b 4) b) (else 0)))) (f 3))` | `6` |
