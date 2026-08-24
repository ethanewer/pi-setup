# Ledger pools: make DEBUG and RELEASE behave identically and correctly

`/app/cashier` is a C++17 program: a small "ledger" (`cashier`) that keeps live
rows inside a custom fixed-slot **cell pool** (`Pool`). It reads an op file and
prints ledger lines to stdout. The pool is built two ways:

```
make debug     # -O0 -g -DDEBUG_CHECKPOOL   diagnostic checks active
make release   # -O2 -DNDEBUG               production-like
```

These two builds **must be behaviorally identical**: given the same input they
must print the same stdout and exit 0. Right now they are not, and one of the
runs also disagrees with the true ledger shown in `/app/cashier/README.md`.

## What to do

1. **Read** `/app/cashier/README.md` first — it defines the op language
   (`N/W/F/T/S`), the pool contract, and the build modes.
2. **Reproduce.** Run `./check.sh` (or run `make` and then
   `./build/debug/cashier --input cases.txt` and
   `./build/release/cashier --input cases.txt`). Record which mode fails, how
   it fails (exit code / `POOLDIAG:` diagnostic / wrong numbers), for both
   `cases.txt`.
3. **Isolate the smallest failing case.** Use `python3 reduce.py` (it
   simulates the *correct* ledger and finds the shortest op prefix that makes
   the release build diverge). Also hand-check a 2–3 op example with gdb if
   useful: `gdb ./build/debug/cashier` with a breakpoint inside
   `Pool::alloc`/`Pool::dealloc` and inspect `free_`/`c`.
4. **Compare build modes.** Note precisely what differs between the two flags:
   a crash-with-diagnostic in one mode versus silent wrong numbers in the
   other is the key signal.
5. **Fix the defect(s).** You may edit **exactly one file**: `pool.cpp`. All
   other files (`pool.h`, `main.cpp`, `Makefile`, `cases.txt`, `README.md`,
   `check.sh`, `reduce.py`) are immutable — the verifier hashes them.
   Rebuild and re-run until both modes are identical **and** match the true
   ledger (verify against `python3 reduce.py` semantics or a small independent
   script).
6. Make sure `make` (both targets) still builds with zero errors and expect a
   clean run: final check `./check.sh` should show identical debug/release
   output with exit 0 on the same input.

## Acceptance (what the verifier computes)

- All immutable files above are byte-for-byte unchanged.
- `make debug release` succeeds.
- Both binaries exit 0 and print **identical** stdout for `cases.txt`
  (mode parity).
- The stdout equals the true ledger for `cases.txt`, recomputed
  independently: sums of live row balances for each `S`, hex `tag` of 16
  zero bytes for each `T`, and a final `LIVE <n>/<16>` occupancy line.

Note: the allocator contract (README) requires `alloc()` to hand out cells
whose payload bytes are zero — stale bytes must not leak into fresh cells,
in any build mode.