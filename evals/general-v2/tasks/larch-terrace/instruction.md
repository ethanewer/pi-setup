# larch-terrace — the Dogleg porting lab

## Objective

Your compute lab, **Dogleg**, keeps several legacy build jobs running. Your job is
to produce **six deliverables** under `/app`. All inputs are given; none of the
`/app/...` sources you are provided may be edited — instead you write fresh build
files and programs. The verifier reruns and re-executes every deliverable on its
own inputs, so each artifact below must be a *real, runnable* object, not a
placeholder.

Provided fixtures (already in your container, do NOT modify):

```
/app/src/game.c                  # a tiny C "game": reads n, prints sum 1..n
/app/src/fseries/series_mod.f90  # Fortran library module (function sum_squares)
/app/src/fseries/main_series.f90 # Fortran main: reads n, prints sum of squares 1..n
/app/src/fseries/Makefile.legacy # a Makefile written for the *Intel/PG* frontend
```

The `.f90` sources and `game.c` must remain byte-for-byte unchanged.

---

## Deliverable 1 — `/app/game.mips` (cross-compiled little-endian MIPS)

Cross-compile `/app/src/game.c` with the **little-endian MIPS** toolchain into
`/app/game.mips`. It must be a MIPS (little-endian) ELF executable that runs under
`qemu-user-static` on this x86_64 host, e.g.:

```
mipsel-linux-gnu-gcc -static -O2 -o /app/game.mips /app/src/game.c
```

Behaviour (unchanged from the source): read one integer `n` from stdin, print
`sum(1..n)` followed by a newline. If you build dynamically, set
`QEMU_LD_PREFIX=/usr/mipsel-linux-gnu` when running it; a static binary needs no
prefix. The verifier runs it via `qemu-mipsel-static /app/game.mips` on hidden `n`.

## Deliverable 2 — `/app/main` and `/app/Makefile` (gfortran retarget)

The two Fortran sources are written for, and build-rule-flags target, the
**legacy Intel/PG frontend** that is NOT installed here. Write a **new**
`/app/Makefile` that rebuilds the exact same two sources with **gfortran** into the
executable `/app/main`. Do not edit either `.f90` file.

- `/app/Makefile` must mention `gfortran` and must NOT reference the legacy
  frontend (`ifort`, `pgfortran`, `pgf90`, `flang`).
- `make -f /app/Makefile` (from `/app`) must build `/app/main`; the verifier runs
  `make clean` then `make` to prove it works from scratch.
- `/app/main` reads one integer `n` on stdin and prints the sum of squares
  `1^2+...+n^2` as a bare integer, e.g. `n=10` -> `385`.

`/app/src/fseries/Makefile.legacy` is provided for reference only — do not rebuild
with it and do not edit the fixtures.

## Deliverable 3 — `/app/poly.c` (a genuine C/Python polyglot)

Author a **single source file** `/app/poly.c` that is *valid as both* a C program
and a Python 3 program, and that behaves differently under each toolchain:

- compiled with `gcc -x c` and run, it must print exactly `LANG:C` on stdout;
- executed with `python3 /app/poly.c`, it must print exactly `LANG:PY` on stdout.

Both runs must succeed (exit 0). This is the classic dual-parser construction: one
region of the file is real C (hidden from the Python parser) and another is real
Python (hidden from the C preprocessor) — e.g. using nested `#if 0`/`#endif` regions
that toggle which toolchain sees live code while a `"""` string shields the C text
from Python. The file must parse cleanly under `python3` even though it also
contains a full `int main`.

## Deliverable 4 — `/app/app.c` + `/app/app` (arg-max autoregressive sampler in C)

Implement, in **plain C**, a self-contained argument-maximum autoregressive
generative sampler: a toy transformer whose forward pass picks the single most
probable next token at each step and feeds it back into the context. Two files:
the source `/app/app.c` and the compiled executable `/app/app` (build with
`gcc -O2 -o /app/app /app/app.c`).

**Architecture (exact, deterministic, all-integer — do not change):**

```
V = 23              # vocabulary size, tokens 0..22
D = 8               # hidden/embedding width
emb(t, i) = (t*5 + i*7 + 1) % 9
w1(i, j) = (i*3 + j*11) % 7 - 3
b1(j)    = (j*13) % 5 - 2
w2(j, k) = (j*17 + k*5) % 7 - 3
b2(k)    = (k*3) % 5 - 2
relu(x)  = x > 0 ? x : 0
```

**IO / algorithm.** The program reads one line from stdin:
`L n t1 t2 ... tn` — `L` = number of tokens to generate, `n` = prompt length, then
the prompt token ids. It prints `L` space-separated generated token ids followed by
a newline. Generation is autogressive: maintain a context list that starts as the
prompt; repeatedly compute the next token and append it:

```
ctx  = the prompt (n tokens)
1. context vector c[i] = sum over every token t in ctx of emb(t, i), for i in 0..D-1
2. hidden  h[j] = relu( b1(j) + sum_{i in 0..D-1} c[i] * w1(i,j) ),  j in 0..D-1
3. logits[k]     = b2(k) + sum_{j in 0..D-1} h[j] * w2(j,k),        k in 0..V-1
4. next = argmax_k logits[k]   (on ties take the SMALLEST index k)
5. append next to ctx; record it; repeat L times
```

Because the model is fully integer and deterministic, the continuation is exact.
Keep the implementation **modular**: split the code into at least **4** named
helper functions (e.g. embedding, the two weight/bias tables, the single forward
pass, the feed-back loop). Keep the whole `/app/app.c` source **compact**: its
`gzip -c` size must stay under **3000 bytes**.

Example (illustration of the I/O shape only — verify your own build):

```
$ echo "4 3 1 2 3" | ./app
19 19 19 19
```

## Deliverable 5 — `/app/scheme.py` (metacircular evaluator)

Write a small **Scheme interpreter in Python**: a metacircular evaluator with an
environment (lexical scoping), first-class **closures** via `lambda`/`apply`, and
the core special forms. It reads Scheme source from stdin (several top-level forms
allowed), evaluates each form, and prints each non-`define` result on its own line
in Scheme display form (integers as their value, `#t`/`#f` for booleans, lists as
`(a b c)`).

Must support at least: integer arithmetic `+ - * /`, `quote`, `if`, `define`
(including `(define (name args...) body)` sugar), `lambda` with closures, `begin`,
`eq?  =  <  >`, `car  cdr  cons  list`, and the predicates `null?  list?  number?`.
Do NOT use `eval`/`exec` to implement it (a metacircular evaluator writes its own
`eval`/`apply`). Example:

```
$ printf '(define (fact n) (if (< n 2) 1 (* n (fact (- n 1)))))\n(fact 6)\n' | python3 /app/scheme.py
720
```

---

## Notes

- Do not edit or delete any of the provided fixtures in `/app/src`.
- Every deliverable must exist at its exact path. All programs must be executable.
- The verifier re-runs the MIPS binary under qemu, re-runs `make` with your
  `/app/Makefile`, re-compiles and re-runs the polyglot under *both* toolchains,
  drives `/app/app` on hidden prompts, and evaluates hidden Scheme programs.
- Work strictly inside your container's `/app`; do not touch `/tests` or anything
  outside your working area.
