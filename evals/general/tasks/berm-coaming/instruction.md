# Errors raised inside a `list_reduce` lambda surface as an INTERNAL error

## Situation

`/app/src` is a shallow, pinned clone of the DuckDB source repository
(`https://github.com/duckdb/duckdb`) at an upstream commit, checked out in
detached HEAD at exactly one commit. The release engine has already been
configured and compiled in place, so everything works entirely offline:
outbound network is not guaranteed and must not be relied on (`git fetch`,
`curl` and any other network use will fail).

The prebuilt CLI binary is `/app/src/build/release/duckdb` and the project's
own test runner is `/app/src/build/release/test/unittest`. Because the build
is already done, editing a C++ source file and rebuilding is an incremental
recompile plus a relink:

```
cd /app/src && ninja -C build/release
```

Each cycle is on the order of half a minute to a minute, not hours. Do
**not** reconfigure or clean the `build/release` directory, and do not
modify `.git`.

## The bug

DuckDB's `list_reduce(list, lambda)` applies a lambda left-to-right over the
elements of a list. When the lambda raises an error at runtime — for example
because it calls the `error('...')` function, or because a cast inside it
fails — the query does fail, but with a misleading message. Instead of
seeing the error the lambda actually raised, users see this:

```
INTERNAL Error: Scalar function "list_reduce" threw an execution error, but the function is not marked as fallible - the function must call SetFallible(). Error: <the lambda's own message>

Stack Trace:
...
```

followed by a stack trace of engine internals. Compare with the sibling list
functions (`list_transform`, `list_filter`): an error raised in their
lambdas surfaces as an ordinary user-facing error (`Invalid Input Error:
...` or `Conversion Error: ...`), with the lambda's own message and no stack
trace. Errors raised inside a `list_reduce` lambda should propagate the same
way.

## What you need to do

1. **First, write your own failing reproduction.** Create an executable
   script `/app/repro.sh` whose contract is:

   - `bash /app/repro.sh` runs a `list_reduce` query whose lambda raises an
     error at runtime, against the default binary
     `/app/src/build/release/duckdb`, and prints exactly one line:
     `REPRO-PASS` when the error surfaced as the lambda's own clean
     user-facing error with **no** `INTERNAL Error` in the output;
     `REPRO-FAIL` otherwise. It must exit `0` after `REPRO-PASS` and
     non-zero after `REPRO-FAIL`.
   - `bash /app/repro.sh <path-to-a-duckdb-binary>` runs the **same query**
     against the given binary, so the same script can probe two different
     engines.

   Run it against the current (broken) engine first: it must print
   `REPRO-FAIL`. Keep it runnable in both forms.

2. **Then fix the bug** in the checked-out tree at `/app/src` so that errors
   raised inside a `list_reduce` lambda surface as clean user-facing errors
   (no `INTERNAL Error`, no stack trace), while `list_reduce` keeps working
   exactly as before when no error occurs: any reduction that previously
   returned a value must still return the same value.

   Verify with the project's own machinery. The relevant existing
   sqllogictest file is `test/sql/function/list/lambdas/reduce.test`; run it
   through the project's own runner:

   ```
   cd /app/src && build/release/test/unittest "test/sql/function/list/lambdas/reduce.test"
   ```

   It currently passes; after your fix it must still pass. The other files
   under `test/sql/function/list/lambdas/` must stay green too, e.g.:

   ```
   cd /app/src && build/release/test/unittest "test/sql/function/list/lambdas/*"
   ```

3. Write `/app/summary.md` — a non-empty write-up of what the bug was, what
   you changed, and how you verified it.

## Constraints

- The clone at `/app/src` is the deliverable. Change in place only what the
  fix requires: do not rewrite history, add remotes, fetch, commit, stage,
  or change build configuration, and do not add, move, rename or delete
  files inside the repository. The verifier expects exactly **one**
  modified tracked source file (the C++ source file the bug lives in) with a
  real diff, and nothing else changed. Delete any scratch files you create
  before you finish.
- `/app/repro.sh` and `/app/summary.md` are deliverables at `/app`.
  `/opt/golden`, `/opt/pre-fix`, `/tests` and `/solution` are
  harness-owned; do not modify them.
- Outbound network must not be relied on; everything needed is installed and
  prebuilt in the image.

## What the verifier checks

1. Tree provenance: still at the pinned commit; the upstream fix commit is
   not reachable from the clone's object store; exactly one source file
   modified with a real diff; nothing else changed; no stray untracked
   files.
2. A forced incremental rebuild from the repaired tree — the project's
   binaries are deleted and relinked from your actual sources by the
   project's own build system — after which the project's **own regression
   test** for this bug (baked into the image at `/opt/golden` and planted by
   the verifier over `test/sql/function/list/lambdas/reduce.test`) passes
   through the project's own runner, and the rest of the
   `test/sql/function/list/lambdas` suites stay green.
3. `/app/repro.sh` is executed twice: pointed at a pre-fix engine snapshot
   (`/opt/pre-fix/duckdb`) it must print `REPRO-FAIL` (it genuinely detects
   the bug on the broken engine), and pointed at the repaired engine it must
   print `REPRO-PASS`. The same must hold when the pre-fix snapshot is
   invoked through a copy at a different path.
4. Authored hidden cases: further `list_reduce` queries whose lambdas raise
   errors through inputs the upstream regression test does not use —
   different list contents and lengths, distinct error messages, BOOLEAN /
   DOUBLE / string elements, BIGINT / HUGEINT cast failures, an error
   raised only after several successful reduction steps — plus successful
   reductions that must keep returning their exact values. Each hidden check
   is run against both the pre-fix snapshot and the repaired engine.

Deliverables: the repaired `/app/src` tree, the executable `/app/repro.sh`,
and `/app/summary.md`.