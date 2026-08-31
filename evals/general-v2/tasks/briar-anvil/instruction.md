# Repair the `memledger` lifecycle — correct output, zero leaks, no shortcuts

You are working inside `/app` in a container. `memledger` is a small C tool
that replays an allocation ledger; its stdout is already correct, but it
short-circuits process exit from inside its processing loop, so the cleanup
lifecycle never runs and a leak checker reports definite leaks. Fix the
lifecycle **in source**.

## Tool behavior (the contract)

`memledger` is invoked as `/app/src/memledger <file>`. It reads the file line
by line (trailing `\r` stripped, so CRLF files work). Each line is exactly one
of:

- `alloc <label> <size>` — register an active record. `label` is
  `[A-Za-z0-9_]+`; `size` is a non-negative decimal integer (e.g. `0`, `007`
  is allowed and means 7). Allocating an already-active label is **malformed**.
- `free <label>` — release the active record for `label`. Freeing an unknown
  label is **malformed**.
- `finish` — stop reading; every line after it is ignored entirely (not even
  counted). The end-of-run report is still printed exactly once.
- Anything else — leading/trailing/double spaces, empty lines, unknown
  commands, missing fields, non-digit sizes, `finish` with trailing text — is
  **malformed** and only counted.

When reading ends (or `finish` is seen), print one
`active:<label>=<size>` line per still-active record in ascending ASCII order
of label, then a final line `totals:allocs=<A>,bytes=<B>,errors=<E>` where
`<A>`/`<B>` count only successful allocations and `<E>` the malformed-line
count. Exit status 0. Example:

```
active:beta=40
active:delta=0
totals:allocs=4,bytes=53,errors=3
```

## The shipped defect (in `/app/src/ledger.c`)

On the `finish` line, `finish_and_report()` prints the report and then calls
`exit(0)` from inside `process()`. The report bytes are correct, but the
process dies before `main()` can unwind: the active-record table (and every
duplicated label string), the line buffer, and the heap-allocated global
`g_stats` block are never freed, so Valgrind reports definite leaks.

Repair `ledger.c` so the `finish` path **returns normally** and the full
cleanup lifecycle runs: free every table node and label string, free the line
buffer, free the global stats block (`release_globals()`), then print the
report from `main()` and return 0. The program must pass
`valgrind --leak-check=full` with **zero definite leaks** on every input, with
no suppression file and no exit/short-circuit hack.

## Hygiene rules (enforced)

- **Only `/app/src/ledger.c` may be modified.** `src/util.c`, `src/util.h`,
  `src/Makefile`, and `/app/sample.ledger` must stay byte-identical (hashes
  are checked).
- The repaired `ledger.c` must not contain `exit(`, `_exit(`, `_Exit(`, or
  `abort(` anywhere — cleanup must happen by normal returns.
- Do not create files outside the build artifact `/app/src/memledger`.

## Building

`make -C /app/src` builds `/app/src/memledger` (`gcc -g -O0 -Wall -Wextra
-std=c11`); it must compile cleanly. Sanity-check on the visible sample and
under Valgrind:

```bash
make -C /app/src
/app/src/memledger /app/sample.ledger
valgrind --leak-check=full /app/src/memledger /app/sample.ledger
```

## Deliverables (both required)

1. `/app/src/ledger.c` — the repaired source (the only modified file).
2. `/app/src/memledger` — built from the repaired source.

The verifier recompiles from your delivered `ledger.c` and runs the tool
under Valgrind (`--leak-check=full`) on the visible `/app/sample.ledger` and
on several hidden ledger files — including a `finish` line mid-file with junk
after it, `finish` as the first line, all-malformed files, an empty file, a
last line without a trailing newline, CRLF line endings, duplicate
allocations, freeing unknown labels, re-allocating freed labels, and
case-sensitive sort order — comparing stdout byte-for-byte, requiring exit
status 0 and zero definite leaks in every case.
