# Ledger pools (advanced): three allocator defects, three build-mode signals

`/app/cashier` is a C++17 "ledger" (`cashier`) that keeps live rows inside a
custom fixed-slot **cell pool** (`Pool`). It reads an op file and prints ledger
lines to stdout. Two build modes exist and **must be behaviorally identical**:

```
make debug     # -O0 -g -DDEBUG_CHECKPOOL   diagnostic checks active
make release   # -O2 -DNDEBUG               production-like
```

They are not identical today, in more than one way, and the production build
also returns values that disagree with the true ledger.

## Context (read first)

- `/app/cashier/README.md` — op language (`N/W/F/T/S`), pool contract, build
  modes. This is authoritative.

## Working plan

1. **Reproduce.** `./check.sh` runs both builds on `cases.txt`. Record for
   each mode: exit code, any `POOLDIAG:` diagnostic, and the printed numbers.
2. **Isolate.** `python3 reduce.py` finds the shortest op prefix where the
   release build diverges from the true ledger. Use gdb (`-g` is on for both
   targets) to watch `free_`/`c` inside `Pool::alloc` and `Pool::dealloc`
   across the failing ops.
3. **Compare build modes.** The *combination* of signals matters:
   - a crash-with-diagnostic in one mode vs silent wrong numbers in the other,
   - a residue difference that persists after your first fix,
   - divergence that only appears for particular alloc/free patterns.
4. **Fix every defect.** You may edit **exactly one file**: `pool.cpp`.
   All other files (`pool.h`, `main.cpp`, `Makefile`, `cases.txt`,
   `README.md`, `check.sh`, `reduce.py`) are immutable — the verifier hashes
   them. Rebuild and re-run until both modes agree with each other and with
   the true ledger, on `cases.txt` and on fresh patterns you invent
   (especially: **free a cell, then allocate twice**).
5. **Write the required isolation artifact:**
   - `/app/isolation/repro.txt` — the shortest op prefix you found that still
     reproduces a failure before your fix (valid ops only, at least two lines);
   - `/app/isolation/notes.txt` — a short evidence log: what the debug build
     reported (diagnostic text / exit code) versus what release printed, and
     the first diverging ledger line (e.g. "release S line 2 is 46, true 18").

## Acceptance (what the verifier computes)

- All immutable files byte-for-byte unchanged.
- `make debug release` succeeds.
- **Visible case** (`cases.txt`): both binaries exit 0 and print identical
  stdout, and the release stdout equals the true ledger
  (per-`S` sums of live row balances, hex tags on `T`, final `LIVE <n>/16`).
- **Hidden workloads**: three generated op files — free/realloc churn, an
  exhaustion + guard pattern, out-of-range rowids — each must produce the true
  ledger in both modes.
- **Determinism**: two consecutive release runs on `cases.txt` are identical.
- The isolation artifact exists and its `notes.txt` documents the `POOLDIAG`
  mode evidence.

The allocator contract (README) requires `alloc()` to hand out cells whose
payload bytes are zero (no stale bytes) in **every** build mode.