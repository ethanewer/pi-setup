#!/bin/bash
# Oracle solution for item-070-hard.
# Regenerate configure with autoreconf, build vendored SQLite with gcov
# coverage, install on PATH, run behavior + shell probes, write artifacts.
set -euo pipefail

cd /app/src

# 1. Vendor integrity (tarball sha + confirm no top-level configure inside).
VENDOR_SHA=$(sha256sum sqlite-autoconf-3460100-nocfg.tar.gz | awk '{print $1}')
test "$VENDOR_SHA" = "d1fc5e3d1e0f78273d319eacb4cc2ffde428904c3445cff1fbe127becc1bfc54"
if tar tzf sqlite-autoconf-3460100-nocfg.tar.gz | grep -qE 'sqlite-autoconf-3460100/(tea/)?configure$'; then
  echo "unexpected configure in tarball" >&2; exit 1
fi

# 2. Extract in-tree.
tar xzf sqlite-autoconf-3460100-nocfg.tar.gz
cd sqlite-autoconf-3460100

# 3. Regenerate configure from autotools sources.
autoreconf -fi >/tmp/autoreconf.log 2>&1
test -f configure
test configure -nt configure.ac

# 4. Configure with deliberate coverage flags.
CFLAGS="-O2 -g --coverage -DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_FTS5_PARENTHESIS -DSQLITE_ENABLE_MATH_FUNCTIONS" \
  ./configure --prefix=/usr/local --disable-shared --enable-static >/tmp/configure.log 2>&1

# 5. Build + install.
make -j2 >/tmp/make.log 2>&1
make install >/tmp/make_install.log 2>&1
test -x /usr/local/bin/sqlite3
test -f /usr/local/lib/libsqlite3.a
test "$(command -v sqlite3)" = "/usr/local/bin/sqlite3"

# Behavior + coverage accumulation.
rm -f /app/data/smoke.db*
for i in 1 2 3 4; do
  sqlite3 /app/data/smoke.db < /app/data/corpus-hard.sql >/dev/null 2>&1 || true
done

B1=$(sqlite3 :memory: "select sqlite_version();")
B2=$(sqlite3 :memory: "select json_extract('{\"a\":7}','$.a');")
B3=$(sqlite3 :memory: "CREATE VIRTUAL TABLE t USING fts5(c); INSERT INTO t VALUES ('one'),('two'); SELECT count(*) FROM t WHERE t MATCH 'one OR two';")
B4=$(sqlite3 :memory: "select round(sin(0.0),4), round(cos(0.0),4);")

test "$B1" = "3.46.1"
test "$B2" = "7"
test "$B3" = "2"
test "$B4" = "0.0|1.0"

# Dot-command probe.
rm -f /app/data/verify.db
sqlite3 /app/data/verify.db < /app/data/corpus-hard.sql >/dev/null 2>&1 || true
TABLES=$(sqlite3 /app/data/verify.db ".tables")
echo "$TABLES" | grep -q users
echo "$TABLES" | grep -q docs
SCHEMA=$(sqlite3 /app/data/verify.db ".schema users")
echo "$SCHEMA" | grep -q "CREATE TABLE users"

# CSV import probe.
sqlite3 /app/data/verify.db "CREATE TABLE IF NOT EXISTS imported(id INTEGER, name TEXT, score REAL);" >/dev/null
sqlite3 /app/data/verify.db ".import --csv /app/data/import.csv imported" >/dev/null 2>&1 || true
C5=$(sqlite3 /app/data/verify.db "SELECT count(*) FROM imported;" 2>/dev/null)
test "$C5" = "3"

# 6. Coverage artifacts.
gcov -n -o sqlite3-sqlite3.o sqlite3.c > /tmp/gcov_hard.txt 2>&1
mkdir -p /app/artifacts
cp /tmp/gcov_hard.txt /app/artifacts/coverage-summary.txt

LINE=$(grep -oE "Lines executed:[0-9.]+% of [0-9]+" /tmp/gcov_hard.txt | head -1)
PCT=$(echo "$LINE" | sed -E 's/Lines executed:([0-9.]+)% of ([0-9]+)/\1/')
TOT=$(echo "$LINE" | sed -E 's/Lines executed:([0-9.]+)% of ([0-9]+)/\2/')
test -n "$PCT" && test -n "$TOT"

# sqlite3.c sha (vendored exactness).
SQLITE3_C_SHA=$(sha256sum sqlite3.c | awk '{print $1}')
test "$SQLITE3_C_SHA" = "6c35bc5f7f85eac9c49928bacbb02bb694b547aabf69197e058cca245ad80e83"

# 7. Artifact contract.
cat > /app/artifacts/report.json <<EOF
{
  "sqlite_version": "3.46.1",
  "vendor_tarball_sha256": "$VENDOR_SHA",
  "sqlite3_c_sha256": "$SQLITE3_C_SHA",
  "build_dir": "/app/src/sqlite-autoconf-3460100",
  "regeneration": "autoreconf -fi",
  "configure_command": "./configure --prefix=/usr/local --disable-shared --enable-static",
  "cflags": "-O2 -g --coverage -DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_FTS5_PARENTHESIS -DSQLITE_ENABLE_MATH_FUNCTIONS",
  "gcov_lines_executed_pct": $PCT,
  "gcov_total_lines": $TOT,
  "behavior_checks": {"version_matches": true, "json_ok": true, "fts5_ok": true, "math_ok": true, "dot_commands_ok": true, "import_csv_ok": true},
  "path_install_ok": true
}
EOF

echo "OK: sqlite3 (regen + coverage) installed on PATH."