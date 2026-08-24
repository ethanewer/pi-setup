# Item-070 (medium) — Build vendored SQLite with coverage, install it on PATH

You are the build engineer for a data-tooling team. The team needs a **fresh
SQLite build from the exact vendored source tarball** in this container,
compiled with deliberate, documented flags, **instrumented for line coverage
(gcov)** so the QA group can see what the smoke suite exercises, and **installed
on the system PATH** so any script can run `sqlite3`. Your work must be
reproducible and provable: leave behind artifacts that independently show the
binary works AND that the coverage artifacts are real.

## What is already in the container

- `/app/src/sqlite-autoconf-3460100.tar.gz` — the **vendored** SQLite source
  release tarball (SQLite 3.46.1, autotools layout: `configure`,
  `configure.ac`, `Makefile.am`, `sqlite3.c` amalgamation, …). Use ONLY this
  exact tarball; do not download or pip-install any other SQLite.
  Its SHA-256 is (verify this yourself):
  `67d3fe6d268e6eaddcae3727fce58fcc8e9c53869bdd07a0c61e38ddf2965071`
- `/app/data/corpus.sql` — the QA smoke corpus (schema + FTS5 table + JSON +
  CTEs + window functions + triggers + transactions + math functions + a
  recursive CTE + VACUUM). Deterministic; run it against a scratch database.
- `ubuntu 24.04` with `gcc`/`g++`, `make`, `gcov`, `autoconf`, `automake`,
  `libtool` installed.

## Task

Work in stages; the artifact contract at the end is exact.

### 1. Verify the vendor artifact

Compute `sha256sum /app/src/sqlite-autoconf-3460100.tar.gz` and confirm it
matches the value above. Record it in your report.

### 2. Extract and build in-tree (use the vendored source exactly)

Extract the tarball **so the source tree lives at
`/app/src/sqlite-autoconf-3460100/`** (i.e. `cd /app/src && tar xzf
sqlite-autoconf-3460100.tar.gz`). Build **in-tree** in that directory — do not
move, edit, or replace `sqlite3.c` or any vendored file, and do not delete the
compiled objects afterwards.

### 3. Configure with deliberate compiler flags

Run the provided `./configure` (in `/app/src/sqlite-autoconf-3460100`) with
**exactly these settings**:

```
CFLAGS="-O2 -g --coverage -DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_FTS5_PARENTHESIS -DSQLITE_ENABLE_MATH_FUNCTIONS" ./configure --prefix=/usr/local --disable-shared --enable-static
```

Notes:

- `--coverage` (compiler + linker) is what makes gcov instrumentation work —
  it must be in the flags you actually use.
- `--disable-shared --enable-static` keeps the build simple: one static
  `libsqlite3.a` and one `sqlite3` shell binary.
- `-DSQLITE_ENABLE_FTS5` enables the FTS5 extension used by the smoke corpus.

### 4. Build and install on PATH

```
make -j2
make install
```

`make install` must place the `sqlite3` binary at `/usr/local/bin/sqlite3`
(already on `PATH`). Confirm from an unrelated directory that
`command -v sqlite3` finds it.

### 5. Verify executable behavior (and generate coverage data at the same time)

Every `sqlite3` run below also accumulates `.gcda` coverage files for the
`--coverage` build. Run the smoke corpus a few times and record each result:

```
cd /app/src/sqlite-autoconf-3460100
sqlite3 /app/data/smoke.db < /app/data/corpus.sql
sqlite3 /app/data/smoke.db < /app/data/corpus.sql   # repeat for deeper coverage
sqlite3 /app/data/smoke.db < /app/data/corpus.sql
```

Then verify the four concrete behavior probes and record their outputs
(you may run them from anywhere; they must all succeed):

```
sqlite3 :memory: "select sqlite_version();"                       # -> 3.46.1
sqlite3 :memory: "select json_extract('{\"a\":7}','$.a');"        # -> 7
sqlite3 :memory: "CREATE VIRTUAL TABLE t USING fts5(c); INSERT INTO t VALUES ('one'),('two'); SELECT count(*) FROM t WHERE t MATCH 'one OR two';"   # -> 2
sqlite3 :memory: "select round(sin(0.0),4), round(cos(0.0),4);"   # -> 0.0|1.0
```

### 6. Produce coverage artifacts

From the build directory, run gcov **without** writing the huge per-line file
(`-n` = no output file) and capture its summary:

```
cd /app/src/sqlite-autoconf-3460100
gcov -n -o sqlite3-sqlite3.o sqlite3.c > /tmp/gcov_main.txt 2>&1
cat /tmp/gcov_main.txt
```

(The CLI's instrumented object for the amalgamation is `sqlite3-sqlite3.o` —
automake names program objects `program-source.o`. Point gcov at that object so
it reads the right `.gcno`/`.gcda` pair.)

`gcov` prints a summary line like `Lines executed:51.23% of 218345`. Save this
summary **verbatim** and compute the percentage.

### 7. Write the artifact contract (exact)

Create `/app/artifacts/coverage-summary.txt` containing the **entire verbatim
output of the `gcov -n` command** above (the `File 'sqlite3.c'` and
`Lines executed:…` lines included).

Create `/app/artifacts/report.json` with exactly this shape:

```json
{
  "sqlite_version": "3.46.1",
  "vendor_sha256": "<sha256 of /app/src/sqlite-autoconf-3460100.tar.gz>",
  "build_dir": "/app/src/sqlite-autoconf-3460100",
  "configure_command": "./configure --prefix=/usr/local --disable-shared --enable-static",
  "cflags": "-O2 -g --coverage -DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_FTS5_PARENTHESIS -DSQLITE_ENABLE_MATH_FUNCTIONS",
  "gcov_lines_executed_pct": 51.23,
  "gcov_total_lines": 218345,
  "behavior_checks": {"version_matches": true, "json_ok": true, "fts5_ok": true, "math_ok": true},
  "path_install_ok": true
}
```

Rules:

- `vendor_sha256` must equal the value from step 1.
- `gcov_lines_executed_pct` / `gcov_total_lines` must be the numbers parsed
  from the `Lines executed:… of …` summary line — and the same numbers must be
  recoverable from `coverage-summary.txt` (the verifier parses both).
- `behavior_checks` must all be `true`, and they must genuinely hold (the
  verifier re-runs the same four probes itself).
- `configure_command` and `cflags` must match what you actually ran.

## Grading

The verifier will, from a neutral directory:

1. find `sqlite3` on `PATH` and check its version string,
2. re-run the four behavior probes against the installed binary,
3. re-run `gcov -n -o sqlite3-sqlite3.o sqlite3.c` in the build directory and check that the
   reported line coverage is real: it must be ≥ 5%, and must match the value
   you wrote into `report.json`/`coverage-summary.txt` within ±3 percentage
   points (its own run includes a few extra probes, so small drift is fine),
4. check the SHA-256 you recorded matches the vendored tarball,
5. check `report.json` and `coverage-summary.txt` exist and are well formed.

All checks must pass for full reward.
