# Polyglot Fibonacci: ONE authoritative source, four runtimes

You are a build engineer for the `polyfibo` command-line tool. The team wants a
single hand-authored source file that is simultaneously valid **Python 3**,
valid **C** (compiled by `gcc`), and valid **C++** (compiled by `g++`), plus a
companion **Rust** program that matches it byte-for-byte on stdout. One source
artifact must stay authoritative: there must be **no** separate
`main.py` / `main.c` / `main.cpp` copies.

## Environment

- `ubuntu 24.04` with `python3` (3.12), `gcc` (13.x), `g++` (13.x), `rustc`.
- `/app/polyglot/expected_fib.txt` — fixture of `N<TAB>fib(N)` lines used by
  your test harness (do not modify).
- `/app/polyglot/starter.c` — a working single-language C implementation of the
  exact CLI contract below. You may reuse/edit it; it is *not* the solution (it
  is not a valid Python program yet).

## Fibonacci convention and contract

Fibonacci is 0-indexed: `fib(0)=0, fib(1)=1, fib(2)=1, fib(3)=2, ...`.
Every runtime invocation takes the form:

```
python3 /app/polyglot/main.c N          # Python mode
gcc     /app/polyglot/main.c -o /tmp/cm && /tmp/cm N            # C mode
g++ -x c++ /app/polyglot/main.c -o /tmp/cmm && /tmp/cmm N       # C++ mode
rustc   /app/polyglot/main.rs -o /tmp/rm && /tmp/rm N           # Rust mode
```

All four modes must behave identically:

- exactly one argument required; for any valid integer `N` in `[0, 93]`, print
  exactly one line to stdout: the decimal value of `fib(N)` (fits in an
  unsigned 64-bit integer), followed by a newline, exit code 0;
- for **no argument, a non-numeric argument, or a negative argument**: print a
  single short `error: ...` line to stderr and exit with a non-zero exit code;
- for `N > 93` the behavior is not scored and may be anything (including a
  non-zero exit).

## Deliverables (all under /app/polyglot/)

1. **`main.c`** — the polyglot. One file, the authoritative artifact. It must be:
   - runnable by `python3 3.12` directly (`.c` extension is fine for Python);
   - compilable by `gcc` **and** by `g++ -x c++` with exit code 0;
   - free of dependency on a specific toolchain version (assume only the
     defaults present in this container: C11-compatible gcc, C++17-compatible
     g++, Python 3.12, Rust 1.7x).
   Hint territory (design guidance, not required structure): to keep one file
   readable by several parsers, engineers typically exploit comment/string
   constructs that each grammar resolves differently (e.g. `#`-comment lines vs
   `/* ... */` blocks vs multi-line string literals), combined with C
   preprocessor tokens. Minimize syntax collisions: whatever trick you use must
   not break any of the three grammars.
2. **`main.rs`** — a Rust program (written normally; it need not be a polyglot)
   implementing the same contract with the same expected output as `main.c`.
3. **`run_checks.py`** — your own cross-engine test harness. Plain Python 3
   standard library only (no third-party packages). It must:
   - compile the C and C++ modes (gcc/g++) and the Rust mode (rustc) into
     `/tmp`, then run **all four engines** on every `(N, expected)` row of
     `/app/polyglot/expected_fib.txt`;
   - also test the error behaviors (no arg; `abc`; `-1`) on **each** engine and
     require a non-zero exit code and non-empty stderr;
   - report, per engine, `ENGINE <name>: PASS/FAIL` lines;
   - finish with `ALL PASS` (stdout) and exit code 0 when everything passes,
     otherwise print `FAIL` summary and exit non-zero;
   - also write `/app/polyglot/status.txt` containing `PASS` or `FAIL`.

## Workflow

1. Read the fixture and `starter.c`; note the exact contract.
2. Author `main.c` so that *all three* grammars accept it and produce identical
   output; iterate by running each mode by hand on a few small `N`.
3. Write `main.rs` to match.
4. Write `run_checks.py` and run `python3 /app/polyglot/run_checks.py` until it
   prints `ALL PASS`.
5. Keep only `main.c`, `main.rs`, `run_checks.py` in `/app/polyglot/` (plus the
   shipped fixture files). 

## Verification

The grader will independently re-run all four engines over its own fixed set of
inputs and require exact outputs; it will also require `run_checks.py` to exist
and pass, and `status.txt` to say `PASS`. Only `main.c` may define the C-family
behavior — engines must agree with each other and with the fixture.