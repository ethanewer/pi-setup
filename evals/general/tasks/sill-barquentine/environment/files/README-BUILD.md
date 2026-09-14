# DuckDB — build & test cheat sheet

The real DuckDB source tree lives at `/app/src`, checked out (detached) at a
pinned historical commit. A full Release build already exists at
`/app/src/build/release`, built with CMake + Ninja, so **do not rebuild from
scratch**: the tree was compiled once at image build time and your fixes are
meant to be *incremental*.

## Configuration used (already done, do not reconfigure)

```
cmake -G Ninja -B build/release -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_UNITTESTS=1 -DEXTENSION_STATIC_BUILD=1 \
      -DBUILD_EXTENSIONS=core_functions
```

## Incremental rebuild (the only build action you need)

```bash
cd /app/src
ninja -C build/release          # rebuilds whatever your edit invalidated
```

- You have **1 CPU**. A change to one parser source file costs roughly a
  minute of ninja time; a change inside `build/release` metadata costs
  seconds. Do NOT delete or recreate `build/release` — a clean rebuild from
  scratch does not fit in the trial budget and the grader requires the build
  directory to still exist.
- If ninja complains about a missing `build.ninja`, you deleted the build
  directory; that is a grading failure, not a build problem.

## The command-line shell

```bash
/app/src/build/release/duckdb -c "SELECT 1;"
```

Runs one statement batch in an in-memory database and prints the result.
Errors in SQL appear as `<Type> Error: ...` lines on stderr/stdout.

## The project's own test runner

DuckDB regression tests live in `/app/src/test/sql/...` as `*.test`
(sqllogictest-format) files and are executed by the built unittest binary:

```bash
cd /app/src
./build/release/test/unittest test/sql/catalog/sequence/test_sequence.test   # one file
./build/release/test/unittest "test/sql/catalog/sequence/*"                  # a directory
```

A green run ends with `All tests passed (N assertions in M test cases)`.

## Environment notes

- **No network.** Everything is baked into the image; only incremental ninja
  rebuilds against the existing build directory work.
- `/app/src/.git` exists (detached at the pinned commit). Leave it alone:
  no commits, no fetch, no reset, no checkout of other commits.
- The tree must stay byte-identical to the pinned commit **except for the
  single source file where your fix lives**; scratch files you create inside
  the tree must be removed before you finish.
- `build/` is covered by `.gitignore`; the build directory is expected and
  ignored.