# Ledger simulator on top of a custom cell pool

`/app/cashier` contains a small C++17 "ledger" program (`cashier`) that keeps a
set of live ledger rows in a custom, fixed-slot **cell pool** (`Pool`). The
program reads an ops file and prints results to stdout.

## Layout (everything here is IMMUTABLE except `pool.cpp`)

| file         | role                                                        |
|--------------|-------------------------------------------------------------|
| `pool.h`     | pool interface (do not edit)                                |
| `pool.cpp`   | **the only editable file**                                  |
| `main.cpp`   | ledger driver (do not edit)                                 |
| `Makefile`   | builds `build/debug/cashier` and `build/release/cashier`    |
| `cases.txt`  | input op file (do not edit)                                 |
| `check.sh`   | evaluator: builds both modes and runs them on a case file   |
| `reduce.py`  | helper: finds the smallest failing prefix of an op file     |

## Ops

- `N <rowid>` — allocate a live row (rowid 0..31); no-op if row already live
- `W <rowid> <amount>` — credit <amount> (int64) to the row; no-op if dead
- `F <rowid>` — free the row (no-op if already dead)
- `T <rowid>` — print `<balance> <hex tag>` of the row (16-byte hex tag)
- `S` — print the sum of balances across all live rows
- Program ends by printing `LIVE <n>/<16>` (pool occupancy).

## Pool contract

- `alloc(n)` returns a pointer to 56 usable bytes, zero-filled payload
  (**stale bytes must never leak** into a fresh allocation), or `nullptr`
  when the pool is exhausted.
- `dealloc(p)` returns a previously allocated cell; each live cell is
  deallocated at most once by the driver.

## Build modes

```
make              # builds both
make debug        # -O0 -g -DDEBUG_CHECKPOOL   (diagnostic checks active)
make release      # -O2 -DNDEBUG              (production-like)
```

The two builds are supposed to be **behaviorally identical**: same input
file, same stdout, same exit code. That is the acceptance criterion.