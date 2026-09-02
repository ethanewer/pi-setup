# Fix the `batchstat` shutdown lifecycle — leak-free, no short-circuit

You are working inside `/app` in a container. A small C metric tool fails a
leak check on one of its exit paths. Your job is to repair the shutdown
lifecycle in source — for real, not with a workaround.

## Repository

- `/app/src/batchstat.c` — the tool's logic. This is the **sanctioned file**;
  it is the only source file you may modify.
- `/app/src/tags.c`, `/app/src/tags.h` — validation helpers, provided and
  correct. **Must remain byte-identical.**
- `/app/src/Makefile` — builds `batchstat` via `make -C /app/src`.
  **Must remain byte-identical.**
- `/app/sample_input.txt` — visible fixture. **Must remain byte-identical.**

## Tool contract (already correct except for one path)

`batchstat <input.txt> <report.txt>` reads the input line by line. A valid
line is `TAG VALUE` — exactly one space between them — where:

- `TAG` is `[a-z][a-z0-9_]*` (first char a lowercase letter),
- `VALUE` is an optionally negative decimal integer (`-?[0-9]+`).

Any other line — empty line, uppercase tag, no space, empty/bad value,
trailing junk, tab instead of a space — is **malformed**. Malformed lines are
counted and processing continues.

Behavior:

1. Accumulate the sum of `VALUE` per distinct `TAG` (case-sensitive).
2. If the malformed count exceeds `MAX_ERRORS` (8), print exactly one line
   `aborted:too-many-errors` to stdout and terminate with **exit code 2**.
   The per-tag sums are **not** printed on an aborted run.
3. Otherwise print one line `sum:<TAG>=<total>` per distinct tag in ascending
   byte-wise (`strcmp`) tag order, then `errors:<count>`, and exit 0.
4. The report file must contain **exactly one line**:
   `audit:tags=<n>`, where `<n>` is the number of distinct registry tags
   torn down. It is written by `cleanup_registry()`, which is registered
   with `atexit()` and must run on **both** the success and the aborted
   path, on the way out.

## The shipped bug (in `/app/src/batchstat.c`)

On the too-many-errors abort path, after flushing stdout the code terminates
the process with a raw POSIX termination call (`_exit`). That call
**short-circuits the registered exit lifecycle**:

- the `atexit`-registered `cleanup_registry()` never runs,
- the audit line is never written to the report file,
- the entire registry (entries array plus every tag string) is still on the
  heap at process death, so a leak checker flags the run.

Repair `run()` in `batchstat.c` so the abort path goes through the normal
process lifecycle: terminate the batch with exit code 2 by **returning
normally through `run`/`main` (or calling plain `exit`)** so the registered
cleanup actually runs — the report gets its audit line and every allocation
is freed before the process ends.

## Hygiene rules (enforced)

- **Only `/app/src/batchstat.c` may be modified.** `src/tags.c`,
  `src/tags.h`, `src/Makefile`, and `/app/sample_input.txt` must remain
  byte-identical. Do not create, rename, or delete files under `/app`
  (the build artifact `/app/src/batchstat` is expected).
- **No workarounds:** the fix must be a real lifecycle repair in source.
  The delivered `batchstat.c` must not call `_exit`, `_Exit`,
  `quick_exit`, or `abort`, must not use Valgrind client requests or any
  leak-suppression mechanism, and must keep the `atexit`-registered
  `cleanup_registry` lifecycle intact (both exit paths go through it).
  An audit line must appear exactly once on both paths.
- The tool must build cleanly with the provided Makefile
  (`gcc -g -O0 -Wall -Wextra -std=c11`).

## How it is graded

The verifier recompiles `batchstat` from your delivered `batchstat.c`, then
runs it under Valgrind (`--leak-check=full`) on the visible
`/app/sample_input.txt` and on several hidden input files — including runs
that trigger the too-many-errors abort path with a populated registry. For
every case it compares stdout byte-for-byte, the exit code (0 or 2), the
report file content, and requires that the leak checker finds **no leaked,
reachable, or otherwise in-use blocks at exit** (i.e. the registered
destructor-style cleanup really ran and freed everything).

## Visible sanity check

With `/app/sample_input.txt` as input and any writable report path, a correct
build prints:

```
sum:alpha=15
sum:beta=-5
sum:total=12
errors:3
```

exits 0, and the report contains exactly `audit:tags=3`.
