# Scheme evaluation

`/app/sceval.py` is a small Scheme interpreter written in Python. It reads a `.scm` file and evaluates each top-level form in order:

- a top-level `(define ...)` performs the definition and prints **nothing**;
- every other top-level expression prints its value on its own line (numbers print as integers when exact; lists print as `(a b c)`, symbols print as bare words).

Supported primitives: arithmetic `+ - * / mod abs min max`, comparisons `= < > <= >=`, lists `car cdr cons list null? eq? zero?`, special forms `quote if cond define lambda let begin and or not`. Truthiness follows Scheme: only `#f` is false; everything else (including `0` and `'()`) is true.

## Task

Write a Scheme program at `/app/scheme_prog.scm` that defines and uses these three functions, then run it and capture the output.

1. `(define (square x) (* x x))`
2. `(define (sumsq n) ...)` — recursive function returning the sum of squares `1^2 + 2^2 + ... + n^2`. Base case: `(sumsq 0)` is `0`.
3. `(define (count-even lst) ...)` — recursive function returning how many numbers in the list are even (divisible by 2). Use `(mod x 2)` for divisibility. Base case: `(count-even '())` is `0`.

After the three definitions, the file must end with exactly these two top-level expressions, in this order:

```
(sumsq 5)
(count-even (list 3 1 4 1 5 9 2 6))
```

Run the program and write its output to `/app/scheme_out.txt`:

```
python3 /app/sceval.py /app/scheme_prog.scm > /app/scheme_out.txt
```

`/app/scheme_out.txt` must contain **exactly two lines** (no extra lines, no blank lines): the value of `(sumsq 5)` on the first line and the value of `(count-even (list 3 1 4 1 5 9 2 6))` on the second. Do not print anything else.