# willow-quill — the self-observing closure bench

You are extending the **willow-quill** audit bench. Everything is built from
closures and higher-order functions: state that observes itself, curried
entry points, variadic front-ends, and mutually recursive scanners.

Deliver a single importable module **`/app/pipeline.py`** (Python 3.12,
standard library only) plus the output of running it. Work inside `/app`.
Do not modify `/app/script.txt`.

Run with no arguments, `python3 /app/pipeline.py` must write
**`/app/answer.json`** (see the script contract below). A hidden verifier
will also **import** `/app/pipeline.py` and exercise every function below on
fresh inputs, so implement the exact documented semantics — no hard-coding.

## Required API in /app/pipeline.py

### 1. `make_ledger(start=0)` — stateful closure (self-observing)

Returns a callable `ledger(command, *args)` closed over a hidden balance
(integer, initialized to `start`) and a hidden log of `(command, amount)`
pairs. Behavior:

* `"deposit"`, n — balance += n; append ("deposit", n); return the new balance
* `"withdraw"`, n — balance -= n; append ("withdraw", n); return the new balance
* `"balance"` — return the current balance (nothing logged)
* `"log"` — return a **tuple** of all logged (command, amount) pairs, oldest first
* `"undo"` — if the log is empty, return the balance unchanged; otherwise pop
  the most recent log entry and revert its effect (an undone deposit
  subtracts, an undone withdraw adds), returning the new balance
* any other command, or a missing amount for deposit/withdraw — raise `ValueError`

State persists across calls (the ledger observes its own history).

### 2. `curry3(f)` — currying

Returns `g` such that `g(a)(b)(c)` equals `f(a, b, c)` for any 3-argument
callable `f`. Each top-level call starts a fresh argument triple, so
`g(1)(2)(3)` may be followed by `g(4)(5)(6)` and both must give the right
answers.

### 3. `chain(*fns)` — variadic function composition

Returns a closure `h` such that `h(x)` applies the single-argument functions
in `fns` left to right: `chain(f, g)(x) == g(f(x))`. `chain()` with no
functions is the identity. Works for any number of functions, including one.

### 4. Mutual recursion — the pyrite scanner

A *pyrite* string uses only the characters `(`, `)`, `[`, `]`. A string is
**balanced** when every `(` closes with `)` and every `[` closes with `]`,
properly nested (the empty string is balanced; `([)]` and `((` are not).
Implement the scanner with **two mutually recursive helpers** (one per
bracket kind) — the verifier only checks behavior, but this is the intended
shape.

* `pyrite_balanced(s)` — return `True`/`False` for well-formedness.
* `pyrite_depth(s)` — return the maximum nesting depth of a balanced string
  (`""` → 0, `"()"` → 1, `"[(())]"` → 3). If `s` is **not** balanced, or
  contains any character other than the four bracket characters, raise
  `ValueError`.

### 5. `make_probe()` — variadic self-observing probe

Returns a closure `probe(*vals)` accepting any number of integer arguments
(including zero). Each call returns a dict:

```python
{"n": k, "prev": prev, "out": out}
```

where `k` is the 1-based number of times this probe has been called, `prev`
is the **tuple** of arguments from the previous call (`None` before the first
call), and `out` is `max(vals) - min(vals)` for a non-empty call and `0` for
an empty call. Each `make_probe()` call yields an independent probe.

## The script contract (`/app/script.txt` → `/app/answer.json`)

`main()` (run automatically under `if __name__ == "__main__":`) reads
`/app/script.txt`, applies each non-empty, non-`#` line in order, and writes
`/app/answer.json` — a JSON object `{"results": [...], "count": N}` with one
result per applied line:

* `ledger deposit 50` / `ledger withdraw 20` / `ledger undo` /
  `ledger balance` → the returned balance (integer). The script's ledger
  starts a fresh `make_ledger(0)`.
* `ledger log` → the log as a JSON array of `[command, amount]` pairs.
* `curry A B C` → `curry3(f)(A)(B)(C)` where the script's fixed combiner is
  `f(a, b, c) = a*100 + b*10 + c` (integer).
* `chain f1 f2 ... X` → every token except the last is a single-variable
  expression in `x` (no spaces, e.g. `x+1`, `x*2`); the last token is the
  integer input. The functions apply left to right (an empty function list
  is the identity).
* `pyrite S` → `pyrite_depth(S)` as an integer, or the **string**
  `"error"` if `pyrite_depth` raised `ValueError`.
* `probe V1 V2 ...` → the probe dict, with `prev` serialized as a JSON array
  (or `null`), `out` as computed above. The script uses a fresh
  `make_probe()` probe.

The verifier re-computes the expected `answer.json` from `/app/script.txt`
independently and compares yours.

## Grading summary

* `python3 /app/pipeline.py` runs cleanly and writes `/app/answer.json`;
* `/app/script.txt` is untouched;
* hidden cases import the module and probe every function above with fresh
  inputs: multi-step ledgers (undo edge cases, empty-log undo, unknown
  commands), currying reuse, variadic chains (0, 1, many functions), balanced
  and unbalanced pyrite strings, and probes with empty/repeated calls.
