# printf(%c) produces strings that crash string functions

## Situation

`/app/src` is a shallow, pinned clone of the DuckDB source repository
(`https://github.com/duckdb/duckdb`), checked out in detached HEAD at a
specific upstream commit. The release engine has already been configured and
compiled, so everything works entirely offline. Do **not** rely on the
network: nothing in this task needs it, fetching or installing anything is
prohibited below, and the verifier actively rejects trees whose git object
store contains anything other than the pinned commit.

The prebuilt CLI binary is `/app/src/build/release/duckdb` and the project's
own test runner is `/app/src/build/release/test/unittest`. Because the build
is already done, a source edit only triggers an incremental recompile plus a
relink:

```
cd /app/src && ninja -C build/release -j1
```

Each cycle is on the order of half a minute on this machine's single CPU, not
hours. Do **not** reconfigure or clean the build directory.

## The bug

DuckDB's `printf` string-formatting function supports the `%c` conversion,
which writes a **single raw byte**. The value the user passes is a Unicode
code point, but `%c` ignores the code point and writes only the argument's
low byte. As long as the byte is a printable ASCII byte (0–127) the result is
a normal ASCII string. For a byte in the range 128–255 the result is a string
that is **not valid UTF-8** — and DuckDB's strings are documented and assumed
to always be valid UTF-8, so everything downstream of such a result breaks in
confusing ways:

- Displaying the value fails with a low-level decoding error such as
  `invalid lead byte detected in Utf8Proc::UTF8ToCodepoint, likely due to
  invalid UTF-8`.
- Applying a string function to the value — `lower`, `upper`, `trim`,
  `reverse`, `strip_accents`, anything that has to decode its argument —
  throws an `INTERNAL Error` (for example
  `Scalar function "lower" threw an execution error, but the function is not
  marked as fallible`) followed by a stack trace, and one of them crashes the
  process outright.

A user who writes `printf('%c', ...)` intends to write a character; the
function does not silently corrupt data, but it must not crash the engine
either. The affected behaviour, and the contract a correct engine must
satisfy, is described below. `format` is a sibling syntax of `printf` and
shares its implementation.

## What you need to do

Fix the bug in the checked-out tree at `/app/src` so that the behaviour
above stops happening. Specifically:

1. When a `%c` conversion (or any other format) would produce a result that
   is not valid UTF-8, the query must be rejected with a **clean,
   user-facing** `Invalid Input Error` — that is, a normal error message with
   no stack trace, no `INTERNAL Error`, and no crash — whose text contains
   the phrase `Invalid UTF8 produced by format string` and explains to the
   user that `%c` writes a single byte and points them at `chr(...)` as the
   way to write a Unicode code point. This same error must be raised whether
   the invalid result is displayed directly or passed to a string function
   such as `lower`, `upper`, `trim`, `reverse` or `strip_accents`.
2. Valid input keeps working exactly as before: `%c` with an ASCII byte, all
   other `printf`/`format` conversions, `chr(...)` for code points above 127,
   and `%s` with an already-valid string must all produce the same results as
   at the pinned commit. `format` keeps its own dialect behaviour.

### Deliverable 1: the repaired tree

Fix the engine in place at `/app/src`. The project's own string-function test
suite lives under `test/sql/function/string/` and is runnable with the
project's own runner, e.g.:

```
cd /app/src && build/release/test/unittest "test/sql/function/string/*"
```

The tests in the tree are the spec: the suite and the tree's regression data
must stay green after your change (they are green at the pinned commit).

### Deliverable 2: your own reproduction, `/app/reproduce.sh`

Write an executable bash script at `/app/reproduce.sh` that **you** use to
show the buggy behaviour before fixing anything and to prove the fix after —
no reproduction is provided for you. The script must:

- Accept the engine binary path as its first argument, defaulting to
  `/app/src/build/release/duckdb`, and run the demonstration queries through
  that exact binary (`"$1" -c ...`). It must actually invoke the engine it
  is given; a script that prints canned text without running the engine is
  not a reproduction.
- Cover both faces of the symptom: `%c` with a byte value of at least 128,
  and at least one string function applied to such a `%c` result.
- Print the engine's raw output (stdout and stderr) so the evidence is
  visible.
- Exit with status **0** if and only if the engine under test exhibits the
  fixed behaviour defined in section "What you need to do": every
  demonstration query fails with a clean `Invalid Input Error` whose text
  contains `Invalid UTF8 produced by format string` (no `INTERNAL Error`, no
  stack trace, no crash). Exit **non-zero** otherwise.

The verifier runs your script twice — against the repaired engine you build,
where it must exit 0, and against a preserved snapshot of the pre-fix engine,
where it must exit non-zero — and requires its outputs to differ, so the
script genuinely has to observe the engine it is given. Drive your work with
it: run it against the shipped engine first and watch it fail, fix the tree,
rebuild, and run it again until it passes.

## Constraints

- Network is unavailable; everything needed is installed and prebuilt.
- The clone at `/app/src` is a deliverable. Change in place only what the fix
  requires: do not rewrite history, add remotes, fetch, commit, stage, or
  change build files, and do not add, rename or delete files inside the
  repository — the tree must remain the same clone of the same revision,
  with only the code fix applied to the working tree. In particular, the
  project's own test data files (for example under `test/sql/`) are part of
  the pinned revision and must stay byte-identical to it; the verifier
  checks this.
- `/opt/golden`, `/opt/pristine`, `/tests` and `/solution` are
  harness-owned; do not read or modify them.
- Write your reproduction to `/app/reproduce.sh` (not inside the repository).

## What the verifier checks

1. The tree is still at the pinned commit; the only difference from it is
   the minimal source change, nothing new inside the repository, and the
   regression data under `test/sql/` is byte-identical to the pinned
   revision. The upstream fix commit is not present in the clone's object
   store (exactly one commit is reachable).
2. The engine and test runner are rebuilt incrementally from your repaired
   source (a forced relink, so any planted binary is overwritten) and are
   real executables.
3. The project's own regression test for this bug — the `%c` UTF-8 blocks
   that upstream added to `test/sql/function/string/test_printf.test`,
   extracted at image build time and kept out of your working tree during
   the trial — passes through the project's own `unittest` runner.
4. The project's own `test/sql/function/string/*` suite stays green.
5. Hidden cases through the CLI exercise the same code path from inputs the
   upstream regression does not use: other invalid byte values and positions
   (continuation bytes, a byte >= 128 embedded after other characters,
   multiple `%c`s), string functions the upstream test does not name
   (`upper`, `trim`, `reverse`, `strip_accents`), vectorized execution with
   different row sets, and valid-input sanity checks.
6. `/app/reproduce.sh` is executed twice as described above: it must pass
   against the repaired engine, fail against the preserved pre-fix engine
   snapshot, and print different outputs on the two runs.

Deliverables: the repaired `/app/src` tree and `/app/reproduce.sh`.