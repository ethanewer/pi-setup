# sill-barquentine

You are working inside a real open-source codebase: **DuckDB** — the
in-process analytical SQL engine written in C++ — at a pinned historical
commit in `/app/src` (the working tree starts clean and is fully built, see
`/app/README-BUILD.md`). There is a bug in this tree's `CREATE SEQUENCE`
handling. Your job is to find it, fix it in the working tree, and prove the
fix with the project's own binaries and test suite. You are deliberately
**not** told which file or function to change: localising the bug is part of
the task.

## Environment

- The tree lives at `/app/src` and is writable by you. It is a git clone
  detached at the pinned commit: **do not commit, fetch, reset, checkout
  other commits or otherwise touch `.git`** — the grader requires `HEAD` to
  still be the pinned commit at the end.
- A complete **Release build already exists** at `/app/src/build/release`
  (CMake + Ninja, same flags every DuckDB dev uses). The CLI is
  `/app/src/build/release/duckdb`, the project's own test runner is
  `/app/src/build/release/test/unittest`. After any source change, rebuild
  incrementally with `cd /app/src && ninja -C build/release` (±1 minute on
  this single CPU). Do **not** delete or recreate `build/release` — rebuilding
  from scratch does not fit, and the grader requires the build directory.
- **No network** in this container — nothing can be downloaded.
- **`cpus = 1`**: one vCPU. Keep every command targeted.
- Read `/app/README-BUILD.md` for the exact build/test invocation patterns.

## The bug (user-visible symptom)

`CREATE SEQUENCE` accepts numeric options (`START [WITH]`, `MINVALUE`,
`MAXVALUE`, `INCREMENT [BY]`). When a user passes **`NULL`** as the value of
any of those options — for example from a scripted/parameterised statement —
the server does not report a normal SQL error. Instead the process prints an
**`INTERNAL Error: Calling GetValue on a value that is NULL`** message
labelled an assertion failure, spills a C++ stack trace, and the statement
fails with an unhandled internal error. A user typing

```
CREATE SEQUENCE wrongseq START WITH NULL;
```

gets that internal crash instead of a clear message such as
`Parser Error: ... must not be NULL`. The affected behaviour is: **every
NULL-valued sequence option must be rejected with a clean, descriptive
`Parser Error`, and a valid `CREATE SEQUENCE` with ordinary numeric options
must still work unchanged.**

Reproduce it against the provided tree before you change anything, then make
the smallest possible change that fixes the mechanism (all four options), not
just one input.

## Your job

1. **Write a failing reproduction first.** Before you change any source code,
   write `/app/repro.sh` — your own minimal reproduction of the symptom
   described above. Its contract:

   - It takes **one optional positional argument: the repository directory to
     test** (`/app/repro.sh [REPO_DIR]`), defaulting to `/app/src`.
   - It uses the repository's *own* built CLI at
     `$REPO/build/release/duckdb` (i.e. `/app/repro.sh /some/other/tree`
     tests that tree's binary).
   - It exercises **all four** NULL paths and at least one composed statement:
     `START WITH NULL`, `START NULL`, `MINVALUE NULL`, `MAXVALUE NULL`,
     `INCREMENT BY NULL`, and one statement that combines a NULL option with
     another option in the same `CREATE SEQUENCE` (for example
     `INCREMENT NULL CYCLE`).
   - For every case it runs the CLI with `-c "<statement>"`, prints what the
     CLI actually output (its first few lines), and decides: the case passes
     iff the output contains a `Parser Error:` line naming the offending
     option and does **not** contain `INTERNAL Error`; anything else
     (including the `INTERNAL Error` crash) is a failure of that case.
   - It prints a readable line per case and a final
     `repro: PASS` / `repro: FAIL (N case(s) failed)` summary.
   - It exits **0 if and only if every case passes** (i.e. the bug is gone);
     it exits **non-zero** (the summary printed above is the diagnosis)
     otherwise.
   - It must work no matter what the current working directory is when it is
     invoked, and it must not touch anything outside the repository directory
     it was given plus `/tmp`.

   Confirm, on the **unfixed** tree, that this script fails: it prints the
   `INTERNAL Error` crash for the NULL cases and exits non-zero. Do this
   before fixing anything.

2. **Fix the tree.** Make the smallest possible change so that
   `/app/repro.sh /app/src` exits 0. Fix the mechanism, not just one input:
   the defect is reachable through `START [WITH]`, `MINVALUE`, `MAXVALUE` and
   `INCREMENT [BY]`, in any combination with other options, with any casing of
   keywords (SQL keywords are case-insensitive), and for plain and
   `TEMPORARY` sequences alike (see Grading). Valid `CREATE SEQUENCE`
   statements must keep working exactly as before.

3. **Rebuild and break nothing else.** Rebuild incrementally with
   `ninja -C /app/src/build/release`, then run the project's own regression
   suite for the affected subsystem —
   `cd /app/src && ./build/release/test/unittest "test/sql/catalog/sequence/*"` —
   and confirm it ends with `All tests passed (N assertions in M test cases)`.

4. **The graded tree must be byte-identical to the pinned commit except for
   the single source file where the bug lives.** Do not add, move, delete,
   rename or reformat any file; if you create scratch files to investigate,
   delete them before you finish; make no commits. The grader compares every
   file's bytes against the pinned commit's own blobs, so side-changes also
   fail. Your two authored files `/app/repro.sh` and `/app/summary.md` live
   **outside** `/app/src` and are fine.

5. **Write `/app/summary.md`** — a non-empty write-up: what the bug was, what
   you changed, and how you verified it.

## Working loop (recommended)

1. **Reproduce** with `/app/repro.sh /app/src`. See the `INTERNAL Error` crash
   on every NULL option. Try the sibling shapes (composed statements, other
   option orders, lowercase keywords) to pin down exactly what breaks.
2. **Localise** the bug by reading the code. The SQL parser transforms
   `CREATE SEQUENCE` options into typed values; a `NULL` value must be
   rejected with a descriptive parser error before it is converted. Trace
   where the option values are converted and *why* a `NULL` slips through.
3. **Fix** with the smallest possible change, rebuild, and confirm
   `/app/repro.sh /app/src` exits 0.
4. **Prove nothing else broke**: run the sequence test directory (above) until
   it prints `All tests passed`.
5. Write `/app/summary.md`.

## Deliverables

1. `/app/src` — the repository with your fix applied in the working tree
   (incrementally rebuilt).
2. `/app/repro.sh` — your own failing reproduction, per the contract above.
3. `/app/summary.md` — the write-up.

## Grading

The verifier (the container's own `/tests`) will, on your final tree:

- assert that `HEAD` is still the pinned parent commit, that the upstream fix
  commit is **not** reachable from this clone, and that every tracked file
  except the one source file the bug lives in is byte-identical to that
  commit (any other modification, added file or untracked scratch file fails;
  the bug's source file itself must differ from the pinned commit);
- require `/app/repro.sh` (executable, per its contract, covering all four
  NULL options plus a composed statement) and `/app/summary.md` to exist and
  be non-empty;
- rebuild the tree from your delivered source with the project's own ninja
  build, then run your `/app/repro.sh` against the repaired tree (it must
  pass) **and** against the pristine pre-fix build baked into the image
  (`/opt/prefix/tree`, built from the pinned commit before any fix existed —
  it must fail there, proving the symptom is real and your reproduction
  targets it). The fix must live in the source itself: the grader also
  verifies the delivered source carries the NULL-rejection logic and that
  the executed binaries are genuine products of the project's own build, so
  wrapping results or substituting binaries cannot pass;
- plant the project's **own regression test** for this bug (baked into the
  image at `/opt/golden` — upstream added it with the fix, so it does not
  exist in this tree) and run it with the project's own runner against the
  repaired tree (it must pass), and run the whole
  `test/sql/catalog/sequence/*` directory;
- run authored hidden cases that reach the same code path with inputs the
  upstream regression test does not use (a NULL `START` combined with an
  explicit `INCREMENT`, a `TEMPORARY` sequence with a NULL `MINVALUE`,
  `INCREMENT NULL` without the `BY`, lowercase keywords with a NULL `MAXVALUE`,
  and `START WITH NULL` combined with `CYCLE`), each required to pass on the
  repaired tree and to fail on the pre-fix copy.

Reward is binary: 1 if and only if all of the above hold, otherwise 0.