# Implement integer square root and Fibonacci as logic-gate netlists

## Overview

`/app/netlist.c` is a C program that computes **floor(sqrt(n))** and
**Fibonacci F(k)** by *constructing* a small **logic-gate netlist** — a DAG of
gates — and then evaluating it. The gate machinery, the evaluator, and a CLI +
selftest harness are all provided. Only two public functions are unfinished and
currently return `0`:

```c
ul net_isqrt(ul n);    // floor(sqrt(n))
ul net_fib(int k);     // F(k), k >= 0
```

Complete those two functions so the selftest passes. Do **not** change the
provided gate API, the evaluator, or `main`.

## Gate model (read `/app/netlist.c`)

- Every gate `i` (0..ng-1) stores an opcode plus operand gate **indices**
  (fields `a`, `b`, `c`) or a constant value.
- **Ordering invariant (enforced):** a gate may reference *only* gates with
  indices already emitted (strictly smaller than the new gate). The `op_*`
  builders call `topo()`, which aborts the program if you ever reference an
  operand that has not been created yet. Build operands in paperwork order.
- The evaluator `net_eval()` runs gates in index order (which is already
  topological) and derives each gate's value from its operands.
- `mk_input()`/`set_input(v)`/`net_eval()`/`wire_value(w)` let you feed a value
  through a net you built. All operands you need (OR, MUL, LE, SEL, AND, XOR,
  SUB, ADD, const, input) already exist.

Read the file header and comments before editing.

## What to implement

1. **`net_isqrt(n)`** — build a **bit-serial isqrt circuit** and evaluate it:
   - `r = 0`
   - for bit `b` from `31` down to `0`:
     - `one = 1<<b` (a constant),
     - `cand = r | one`  (OR),
     - `sq   = cand * cand`  (MUL),
     - `keep = (sq <= n)`  (LE produces 1 or 0),
     - `r = keep ? cand : r`  (SEL).
   - Return the netlist result wire's evaluated value = floor(sqrt(n)).
   Build the net with `net_reset()`, create the input with `mk_input()`,
   `set_input(n)`, then `net_eval()` and return `wire_value(result)`.

2. **`net_fib(k)`** — build an **add-chain** netlist computing F(k):
   - `f0 = 0`, `f1 = 1`
   - `for i in 2..k: nxt = f1 + f0; f0 = f1; f1 = nxt` (ADD gate each time).
   - handle `k == 0` (return 0) specially; return `wire_value(f1)`.

Both builders must construct the gates and then *evaluate the netlist* — do
not bypass the netlist to return a cached result.

## Build and verify

Compile and run:

```
gcc -O2 -o netlist /app/netlist.c
./netlist            # selftest => prints SELFTEST_PASS, exit code 0
./netlist isqrt 1000 # => 31
./netlist isqrt 4    # => 2   (CAREFUL: floor sqrt of a perfect square)
./netlist fib 20     # => 6765
```

Test small cases first (0,1,2,3,4,8,9,15,16) before large ones (65535, 123456,
1000000; k up to 30). `isqrt(4)` must be `2`, not `3`.

## Success criteria

- `/app/netlist.c` with your two implementations in place.
- `selftest` prints `SELFTEST_PASS` (exit code 0).
- The `isqrt` and `fib` CLI modes return correct values.