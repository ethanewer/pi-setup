#!/bin/bash
# Oracle solution for item-070-main.
# Build the vendored SQLite with deliberate flags + gcov coverage, install to
# PATH, verify behavior, and emit the artifact contract.
set -euo pipefail

cd /app/src

# 1. Vendor integrity.
sha256sum sqlite-autoconf-3460100.tar.gz
VENDOR_SHA=$(sha256sum sqlite-autoconf-3460100.tar.gz | awk '{print $1}')
test "$VENDOR_SHA" = "67d3fe6d268e6eaddcae3727fce58fcc8e9c53869bdd07a0c61e38ddf2965071"

# 2. Extract in-tree.
tar xzf sqlite-autoconf-3460100.tar.gz
cd sqlite-autoconf-3460100

# 3. Configure with deliberate flags (coverage instrumentation on).
CFLAGS="-O2 -g --coverage -DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_FTS5_PARENTHESIS -DSQLITE_ENABLE_MATH_FUNCTIONS" \
  ./configure --prefix=/usr/local --disable-shared --enable-static >/tmp/configure.log 2>&1

# 4. Build and install on PATH.
make -j2 >/tmp/make.log 2>&1
make install >/tmp/make_install.log 2>&1

command -v sqlite3
test "$(command -v sqlite3)" = "/usr/local/bin/sqlite3"

# 5. Behavior verification + coverage accumulation.
rm -f /app/data/smoke.db*
for i in 1 2 3; do
  sqlite3 /app/data/smoke.db < /app/data/corpus.sql >/dev/null
done

B1=$(sqlite3 :memory: "select sqlite_version();")
B2=$(sqlite3 :memory: "select json_extract('{\"a\":7}','$.a');")
B3=$(sqlite3 :memory: "CREATE VIRTUAL TABLE t USING fts5(c); INSERT INTO t VALUES ('one'),('two'); SELECT count(*) FROM t WHERE t MATCH 'one OR two';")
B4=$(sqlite3 :memory: "select round(sin(0.0),4), round(cos(0.0),4);")

test "$B1" = "3.46.1"
test "$B2" = "7"
test "$B3" = "2"
test "$B4" = "0.0|1.0"

# 6. Coverage artifacts (no per-line file: -n). The CLI's instrumented object
#    for the amalgamation is sqlite3-sqlite3.o (automake program-prefixed).
gcov -n -o sqlite3-sqlite3.o sqlite3.c > /tmp/gcov_main.txt 2>&1
mkdir -p /app/artifacts
cp /tmp/gcov_main.txt /app/artifacts/coverage-summary.txt

PCT=$(grep -oE "Lines executed:[0-9.]+% of [0-9]+" /tmp/gcov_main.txt | head -1 \
      | sed -E 's/Lines executed:([0-9.]+)% of ([0-9]+)/\1/')
TOT=$(grep -oE "Lines executed:[0-9.]+% of [0-9]+" /tmp/gcov_main.txt | head -1 \
      | sed -E 's/Lines executed:([0-9.]+)% of ([0-9]+)/\2/')
test -n "$PCT" && test -n "$TOT"

# 7. Artifact contract.
cat > /app/artifacts/report.json <<EOF
{
  "sqlite_version": "3.46.1",
  "vendor_sha256": "$VENDOR_SHA",
  "build_dir": "/app/src/sqlite-autoconf-3460100",
  "configure_command": "./configure --prefix=/usr/local --disable-shared --enable-static",
  "cflags": "-O2 -g --coverage -DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_FTS5_PARENTHESIS -DSQLITE_ENABLE_MATH_FUNCTIONS",
  "gcov_lines_executed_pct": $PCT,
  "gcov_total_lines": $TOT,
  "behavior_checks": {"version_matches": true, "json_ok": true, "fts5_ok": true, "math_ok": true},
  "path_install_ok": true
}
EOF

echo "OK: sqlite3 installed, coverage artifacts written."
