# Harbor Notch — repair the tally lifecycle so the global destructor runs

You are working inside `/app` in a container. A small C utility, `mtally`,
tallies `KEY=COUNT` lines from a metrics file into a **global registry** whose
memory is released **only by a destructor registered with `atexit()`**. The
shipped copy is broken: on several paths it **short-circuits program exit**
with `_exit()`, which skips the `atexit` destructor, so every run leaks. Your
job is to repair the lifecycle so the program always ends its normal exit path
(destructors included) and Valgrind reports **zero definite leaks**.

## Repository layout

- `src/mtally.c` — the program's main logic (this is the **sanctioned file**;
  it currently contains the bugs).
- `src/store.c`, `src/store.h` — the global tally registry, provided and
  correct. `store_init()` registers `store_free()` **once** via `atexit()`;
  the registry lives in static/global state (`g_head`, plus a global scratch
  buffer) and is released exclusively by that registered destructor.
- `src/Makefile` — `make -C /app/src` builds `mtally` from
  `mtally.c store.c` with `gcc -g -O0 -Wall -Wextra -std=c11`.
- `data/sample.tly` — a small metrics file used for a sanity check.

The tool is invoked as `/app/src/mtally <file>`.

## Line format and required behavior

A **valid** line is exactly `KEY=COUNT` where:

- `KEY` is `[A-Za-z][A-Za-z0-9_]*` (first char a letter, then
  letters/digits/underscore),
- `COUNT` is a non-empty run of decimal digits (a non-negative integer),

and nothing else follows (a trailing carriage return, spaces, or any extra
character makes the line **malformed**). A last line without a trailing
newline is still parsed normally. Any line that does not match — empty lines,
leading whitespace, digit-first keys, missing `=`, empty or non-digit counts,
trailing junk — is **malformed** and must be counted, never fatal.

For a correct run, `mtally` must:

1. Process **every** line of the file. Malformed lines increment the bad-line
   count and the run continues to EOF. (The shipped copy has a vestigial
   "fatal token" panic: any malformed line containing `!` makes it print a
   diagnostic and `_exit(4)`, skipping the rest of the file. In the corrected
   behavior such a line is just malformed.)
2. Accumulate, per distinct `KEY`, the sum of all its `COUNT` values across
   the whole file (case-sensitive, via `store_add`).
3. When reading is done, call `store_report(bad)`, which prints one line
   `tally:<KEY>=<total>` per distinct key in ascending lexicographic
   (`strcmp`) order, then a final line `bad:<count>`, and exit status `0`.
   Example:
   ```
   tally:alpha=15
   tally:beta=4
   bad:1
   ```
4. If the metrics file cannot be opened, print a diagnostic to stderr and
   exit with status `3` — **through the normal exit path**, so the registered
   destructor still runs.
5. Free **every** allocation before the process exits. The program must pass
   `valgrind --leak-check=full` with **zero definite leaks**, with **no
   suppression file**, and with **no premature `_exit()`/`abort()`** that
   short-circuits the atexit-registered cleanup.

### The shipped bugs (all in `src/mtally.c`)

- The happy path ends with `_exit(0)` instead of returning from `main`, so
  the `atexit` destructor never runs — **every** successful run leaks the
  global registry and the global scratch buffer.
- A malformed line containing `!` triggers `_exit(4)`: it leaks everything
  accumulated so far **and** skips the rest of the file.
- An unopenable input file triggers `_exit(3)` after `store_init()`, leaking
  the global scratch buffer.

### The fix

Repair `mtally.c` so all paths return through `main`'s normal exit path:
treat `!`-bearing malformed lines as ordinary malformed lines (count and
continue), return `3` on open failure, and `return 0` after
`store_report(bad)`. Do not cheat: the fix must let the registered destructor
do its job (or perform equivalent real cleanup in source). Bypasses such as
`exit()` on a path that skips remaining input, deregistration tricks,
suppression files, `LD_PRELOAD` shims, or environment overrides all fail the
grader.

### Hygiene rules (enforced byte-for-byte)

- **Only `/app/src/mtally.c` may be modified.** `src/store.c`, `src/store.h`,
  `src/Makefile`, and `data/sample.tly` must remain byte-identical to their
  shipped bytes.
- Do not create, rename, or delete any source/data file in `/app/src` or
  `/app/data`. The build artifact `/app/src/mtally` is expected; nothing else
  new is tolerated in `/app/src`, and no Valgrind suppression files may
  appear anywhere under `/app`.

## Building

Run `make -C /app/src` to produce `/app/src/mtally`. It must compile cleanly
with the provided Makefile. After your fix, sanity-check:

```bash
/app/src/mtally /app/data/sample.tly
valgrind --leak-check=full /app/src/mtally /app/data/sample.tly
```

The verifier will recompile `mtally` from your delivered `mtally.c` and run it
(under Valgrind, with leak errors fatal) on the visible `data/sample.tly`
**and on several hidden metrics files** — a `!`-bearing malformed line in the
middle with valid data after it, a missing input file, a file with no trailing
newline plus CRLF and whitespace-malformed lines, and a clean file — checking
exact stdout, exit status, and zero definite leaks each time.
