# Item-070 (hard) — Rebuild vendored SQLite from configure.ac with gcov, install on PATH

You are the build engineer for a security-conscious data team. A **vendored**
SQLite source release was delivered, but the team has a policy: *never trust a
pre-generated `configure` script — always regenerate it from the autotools
sources in the tree, and prove the amalgamation you compiled is byte-identical
to what the vendor shipped.* You must produce a working, coverage-instrumented
`sqlite3` on the system PATH, verify its behavior (including shell
dot-commands and CSV import), and leave verifiable artifacts.

## What is already in the container

- `/app/src/sqlite-autoconf-3460100-nocfg.tar.gz` — the **vendored** SQLite
  3.46.1 autotools source release, with the pre-generated `configure` scripts
  **deliberately removed** (`configure` and `tea/configure` are absent). What
  remains is the authentic autotools package: `configure.ac`, `Makefile.am`,
  `aclocal.m4`, `ltmain.sh`, `config.guess`, `config.sub`, the `sqlite3.c`
  amalgamation, `shell.c`, `sqlite3.h`, headers, and the `tea/` TCL binding
  (minus its own `configure`). Use ONLY this tarball — no downloads, no
  pip/system SQLite.
  - tarball SHA-256 (verify yourself):
    `d1fc5e3d1e0f78273d319eacb4cc2ffde428904c3445cff1fbe127becc1bfc54`
  - SHA-256 of the `sqlite3.c` **inside the tarball** (this is the canonical
    amalgamation you must compile unchanged):
    `6c35bc5f7f85eac9c49928bacbb02bb694b547aabf69197e058cca245ad80e83`
- `/app/data/corpus-hard.sql` — the QA smoke corpus: schema, FTS5, JSON,
  window functions, recursive CTEs, triggers + views, transactions (incl. a
  savepoint), math functions, `PRAGMA`s, `EXPLAIN`, `VACUUM`, a `CHECK`
  constraint violation path, and a `LIKE`/`GLOB` scan.
- `/app/data/import.csv` — a 3-row CSV fixture for `.import` testing.
- `ubuntu 24.04` with `gcc`/`g++`, `make`, `gcov`, `autoconf` 2.71, `automake`
  1.16, `libtool` installed.

## Task

### 1. Verify the vendor artifact

`sha256sum /app/src/sqlite-autoconf-3460100-nocfg.tar.gz` must equal the value
above; `tar tzf` must NOT list a top-level `configure`. Record both checks.

### 2. Extract (in-tree, exactly as shipped)

`cd /app/src && tar xzf sqlite-autoconf-3460100-nocfg.tar.gz` so the tree is at
`/app/src/sqlite-autoconf-3460100/`. Do not edit any file inside it; do not
delete build products afterwards.

### 3. Regenerate `configure` from the autotools sources (no trust in generated files)

From the tree, run:

```
autoreconf -fi
```

This regenerates `configure` (and friends) from `configure.ac` + `Makefile.am`
+ `aclocal.m4`. Confirm `configure` now exists and that its modification time
is **newer** than `configure.ac` (that is the regeneration proof the verifier
re-checks).

### 4. Configure with deliberate compiler flags

```
CFLAGS="-O2 -g --coverage -DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_FTS5_PARENTHESIS -DSQLITE_ENABLE_MATH_FUNCTIONS" ./configure --prefix=/usr/local --disable-shared --enable-static
```

- `--coverage` must be in the flags actually used (gcov instrumentation).
- Record the exact configure command; it goes into your report.

### 5. Build, install on PATH, verify behavior AND shell integration

```
make -j2
make install
```

`make install` must put `/usr/local/bin/sqlite3` (on PATH) and
`/usr/local/lib/libsqlite3.a`.

Every `sqlite3` invocation also accumulates `.gcda` coverage. Run the smoke
corpus at least four times:

```
cd /app/src/sqlite-autoconf-3460100
sqlite3 /app/data/smoke.db < /app/data/corpus-hard.sql >/dev/null
sqlite3 /app/data/smoke.db < /app/data/corpus-hard.sql >/dev/null
sqlite3 /app/data/smoke.db < /app/data/corpus-hard.sql >/dev/null
sqlite3 /app/data/smoke.db < /app/data/corpus-hard.sql >/dev/null
```

Then verify and record the six probes below (from any directory; all must
succeed):

```
# 1 version            -> 3.46.1
sqlite3 :memory: "select sqlite_version();"
# 2 JSON               -> 7
sqlite3 :memory: "select json_extract('{\"a\":7}','$.a');"
# 3 FTS5               -> 2
sqlite3 :memory: "CREATE VIRTUAL TABLE t USING fts5(c); INSERT INTO t VALUES ('one'),('two'); SELECT count(*) FROM t WHERE t MATCH 'one OR two';"
# 4 math               -> 0.0|1.0
sqlite3 :memory: "select round(sin(0.0),4), round(cos(0.0),4);"
# 5 dot commands       -> .tables lists users AND docs; .schema users contains 'CREATE TABLE users'
rm -f /app/data/verify.db
sqlite3 /app/data/verify.db < /app/data/corpus-hard.sql >/dev/null
sqlite3 /app/data/verify.db ".tables"
sqlite3 /app/data/verify.db ".schema users"
# 6 CSV import         -> 3
sqlite3 /app/data/verify.db "CREATE TABLE IF NOT EXISTS imported(id INTEGER, name TEXT, score REAL);"
sqlite3 /app/data/verify.db ".import --csv /app/data/import.csv imported"
sqlite3 /app/data/verify.db "SELECT count(*) FROM imported;"
```

### 6. Coverage artifacts

```
cd /app/src/sqlite-autoconf-3460100
gcov -n -o sqlite3-sqlite3.o sqlite3.c > /tmp/gcov_hard.txt 2>&1
cat /tmp/gcov_hard.txt
```

(The CLI's instrumented object for the amalgamation is `sqlite3-sqlite3.o` —
automake names program objects `program-source.o`.) `gcov` prints a summary
like `Lines executed:47.21% of 218345`. Save it verbatim.

### 7. Artifact contract (exact)

`/app/artifacts/coverage-summary.txt` = the **entire verbatim output** of the
`gcov -n` command above.

`/app/artifacts/report.json`:

```json
{
  "sqlite_version": "3.46.1",
  "vendor_tarball_sha256": "<sha256 of the nocfg tarball>",
  "sqlite3_c_sha256": "<sha256 of the extracted /app/src/sqlite-autoconf-3460100/sqlite3.c>",
  "build_dir": "/app/src/sqlite-autoconf-3460100",
  "regeneration": "autoreconf -fi",
  "configure_command": "./configure --prefix=/usr/local --disable-shared --enable-static",
  "cflags": "-O2 -g --coverage -DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_FTS5_PARENTHESIS -DSQLITE_ENABLE_MATH_FUNCTIONS",
  "gcov_lines_executed_pct": 47.21,
  "gcov_total_lines": 218345,
  "behavior_checks": {"version_matches": true, "json_ok": true, "fts5_ok": true, "math_ok": true, "dot_commands_ok": true, "import_csv_ok": true},
  "path_install_ok": true
}
```

Rules:

- `vendor_tarball_sha256` and `sqlite3_c_sha256` must match the values you
  computed in steps 1 and 2 (the verifier recomputes both itself).
- `gcov_lines_executed_pct` / `gcov_total_lines` must parse from the
  `Lines executed:… of …` line, and must be recoverable from
  `coverage-summary.txt`.
- `regeneration` must be exactly `autoreconf -fi`, and it must genuinely have
  been done (the verifier checks `configure` is newer than `configure.ac`).
- All `behavior_checks` must be `true` and genuinely hold (verifier re-runs
  all six probes).

## Grading

From a neutral directory the verifier will:

1. check `sqlite3` on PATH, version 3.46.1;
2. re-run all six behavior probes (including dot commands and CSV import);
3. check `/usr/local/lib/libsqlite3.a` exists;
4. re-run `gcov -n -o sqlite3-sqlite3.o sqlite3.c` in the build dir: coverage
   must be ≥ 20%, and within ±3 percentage points of your recorded value;
5. check `configure` is newer than `configure.ac` (regeneration proof);
6. recompute both SHA-256 hashes and compare with your report;
7. validate `report.json`/`coverage-summary.txt`.

All checks must pass for full reward.
