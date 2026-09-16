# Parallel CSV reads return more rows than the file actually contains

## Situation

`/app/src` is a shallow, pinned clone of the DuckDB source repository
(`https://github.com/duckdb/duckdb`), checked out in detached HEAD at a
specific upstream commit. The release engine has already been configured and
compiled, so everything works entirely offline. There is **no network** at
trial time: `git fetch`, `curl` and any other network use will fail.

The prebuilt CLI binary is `/app/src/build/release/duckdb` and the project's
own test runner is `/app/src/build/release/test/unittest`. Because the build
is already done, a source edit only triggers an incremental recompile plus a
relink:

```
cd /app/src && ninja -C build/release
```

Each cycle is on the order of half a minute, not hours. Do **not** reconfigure
or clean the build directory.

## The bug

Reading a CSV file whose lines end with the three-byte sequence CR CR LF
(`\r\r\n` — a line-ending scheme produced by some older Windows-era tools)
with the **parallel** CSV reader can silently return **more rows than the
file actually contains**: rows near buffer boundaries get counted twice, so a
10,000-row file yields 10,002 rows while the **sequential** reader of the
same file returns exactly 10,000. The over-count depends on buffer geometry
(smaller buffers over-count by more), and a `GROUP BY id HAVING count(*) > 1`
over the parallel scan reveals the duplicated rows. The sequential reader is
correct; the bug is in the parallel path, it happens only around buffer
boundaries, and it is specific to `\r\r\n` line endings (`\n` and `\r\n`
files read correctly in both modes). Parallel and sequential scans of the
same file must agree on the row count.

The tree already contains everything the fix targets: a CSV fixture with a
header line plus exactly 10,000 data rows, all ending in `\r\r\n`, at
`data/csv/test/rrrn_parallel_test.csv`, and the project's own regression test
for this bug at `test/sql/copy/csv/parallel/test_rrrn_parallel.test`.

## What you need to do

1. **First, write your own reproduction.** Create an executable script
   `/app/repro.sh` that demonstrates the bug. The script must accept the
   path of a DuckDB CLI binary as its optional first argument (default:
   `/app/src/build/release/duckdb`), run one parallel and one sequential read
   of `data/csv/test/rrrn_parallel_test.csv`, and print exactly one line,
   either `REPRO-PASS` or `REPRO-FAIL`; it must exit `0` after `REPRO-PASS`
   and non-zero after `REPRO-FAIL`. Print `REPRO-PASS` if and only if the two
   counts agree and both equal the true row count (10,000). Use a
   `buffer_size` of 4096 for both reads. Run it against the current (broken)
   engine first: it must print `REPRO-FAIL`. Keep it runnable as both
   `bash /app/repro.sh` and `bash /app/repro.sh <path-to-another-duckdb>`.

2. **Then fix the bug** in the checked-out tree at `/app/src`. The fix must
   be made in the C++ source of the parallel CSV scanner, in place; after the
   fix, rebuild incrementally with `ninja -C build/release` (or
   `ninja -C build/release -j2`). Then all of the following must hold:

   - The project's own regression test for this bug,
     `test/sql/copy/csv/parallel/test_rrrn_parallel.test` (already present
     in the tree), passes through the project's own runner:

     ```
     cd /app/src && build/release/test/unittest "test/sql/copy/csv/parallel/test_rrrn_parallel.test"
     ```

     At the pinned commit it fails (the parallel count is wrong and the
     runner reports `test cases: 1 | 1 failed`); after your fix it must
     print `All tests passed`. The test also re-checks a larger
     `buffer_size` and the absence of duplicated ids, so it will catch an
     over-broad or under-broad fix.

   - Parallel reads of the fixture return exactly 10,000 rows and no
     duplicated ids for **every** buffer size (2048, 4096, 8192, 16384,
     65536, ...); sequential reads are unchanged.

   - Nothing else regresses: files with ordinary `\n` or `\r\n` line endings
     must still read correctly in both modes. Verify with the project's own
     parallel-CSV suites, e.g.:

     ```
     cd /app/src && build/release/test/unittest "test/sql/copy/csv/parallel/test_parallel_csv.test" && build/release/test/unittest "test/sql/copy/csv/parallel/csv_parallel_buffer_size.test" && build/release/test/unittest "test/sql/copy/csv/parallel/csv_parallel_null_option.test" && build/release/test/unittest "test/sql/copy/csv/parallel/test_parallel_error_messages.test" && build/release/test/unittest "test/sql/copy/csv/parallel/test_multiple_files.test" && build/release/test/unittest "test/sql/copy/csv/parallel/parallel_csv_union_by_name.test" && build/release/test/unittest "test/sql/copy/csv/parallel/parallel_csv_hive_partitioning.test"
     ```

   - After the fix, `/app/repro.sh` (unchanged) must print `REPRO-PASS`.

## Constraints

- Network is unavailable; everything needed is installed and prebuilt.
- The clone at `/app/src` is the deliverable. Change in place only what the
  fix requires: do not rewrite history, add remotes, fetch, commit, stage,
  or change build files, and do not add or rename files inside the
  repository. The verifier expects exactly one modified source file under
  `src/` and nothing else changed.
- The regression-test file
  `test/sql/copy/csv/parallel/test_rrrn_parallel.test` and the fixture
  `data/csv/test/rrrn_parallel_test.csv` are part of the image the way the
  fix intends them; the verifier checks that both stay byte-identical.
- `/opt/golden`, `/opt/pre-fix`, `/tests` and `/solution` are harness-owned;
  do not modify them.

## What the verifier checks

1. Tree provenance: still at the pinned commit, single-commit object store,
   exactly one modified source file under `src/` that actually differs,
   nothing else modified, both overlaid test/fixture files byte-identical.
2. A forced incremental rebuild from the repaired tree (the modified file is
   touched, `ninja -C build/release -j2` runs, and the binaries are real ELF
   executables afterwards). The golden regression test passes through the
   project's own runner, and the project's own parallel-CSV suites named
   above stay green.
3. `/app/repro.sh` is executed twice: pointed at a pre-fix engine snapshot
   it must print `REPRO-FAIL` (i.e. it genuinely detects the bug on the
   broken engine), and pointed at the repaired engine it must print
   `REPRO-PASS`.
4. Hidden cases: further `\r\r\n` files with different row counts and row
   layouts than the shipped fixture, read at buffer sizes the regression
   test does not use, must return exactly the true row counts and exact
   aggregate values on the repaired engine. Each hidden check is additionally
   run against the pre-fix engine snapshot to prove it detects the bug there.

Deliverables: the repaired `/app/src` tree and the executable
`/app/repro.sh`.