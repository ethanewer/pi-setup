#!/bin/bash
# Oracle for sill-barquentine: applies the upstream fix to the real
# duckdb/duckdb tree at /app/src (the CREATE SEQUENCE parser transformer must
# reject NULL option values with descriptive ParserExceptions instead of
# hitting Value::GetValue's NULL assertion), writes /app/repro.sh and
# /app/summary.md, then proves the work: the reproduction must fail against a
# scratch copy of the tree with the pre-fix code restored and must pass
# against the fixed tree, and the project's own sequence regression suite must
# stay green. Reads only /app, /solution and the tree's own git objects; never
# /tests.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

# 1) apply the reference fix (reject NULL sequence options)
git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch
echo "oracle: applied the CREATE SEQUENCE NULL-option fix"

# 2) rebuild incrementally (the build is warm from image build time)
ninja -C build/release || { echo "oracle: ninja rebuild failed" >&2; exit 1; }
echo "oracle: rebuild ok"

# 3) the pristine pre-fix tree concept baked into the image at build time
#    (its build/release/duckdb was built from the parent tree before any fix
#    existed; DuckDB's unity build records absolute /app/src include paths, so
#    reconstructed copies cannot be rebuilt faithfully offline and this tree
#    is deliberately never rebuilt).
PREFIX=/opt/prefix/tree
[ -x "$PREFIX/build/release/duckdb" ] || { echo "oracle: pre-fix tree CLI missing" >&2; exit 1; }

# 4) write /app/repro.sh
echo "oracle: writing /app/repro.sh"
cat > /app/repro.sh <<'REPRO'
#!/bin/bash
# Failing reproduction for sill-barquentine: CREATE SEQUENCE with NULL for any
# of START [WITH] / MINVALUE / MAXVALUE / INCREMENT [BY] must yield a clean
# Parser Error naming the option; the pre-fix server crashes with
# "INTERNAL Error: Calling GetValue on a value that is NULL" instead.
# Usage: /app/repro.sh [REPO_DIR]    (defaults to /app/src)
# Contract: run each case through the repository's own CLI, print the output,
# and exit 0 iff every case produces a clean Parser Error naming the option
# and none produces the INTERNAL Error crash.
set -u
REPO="${1:-/app/src}"
CLI="$REPO/build/release/duckdb"
[ -x "$CLI" ] || { echo "repro: CLI not found: $CLI (rebuild the repo first)" >&2; exit 2; }

# statement <TAB> expected parser-error substring
CASES="
CREATE SEQUENCE reproseq START WITH NULL;|START value must not be NULL
CREATE SEQUENCE reproseq START NULL;|START value must not be NULL
CREATE SEQUENCE reproseq MINVALUE NULL;|MINVALUE must not be NULL
CREATE SEQUENCE reproseq MAXVALUE NULL;|MAXVALUE must not be NULL
CREATE SEQUENCE reproseq INCREMENT BY NULL;|INCREMENT must not be NULL
CREATE SEQUENCE reproseq INCREMENT NULL CYCLE;|INCREMENT must not be NULL
"

fails=0
while IFS='|' read -r stmt expect; do
    [ -n "$stmt" ] || continue
    out=$("$CLI" -c "$stmt" 2>&1)
    echo "==> $stmt"
    echo "$out" | head -4 | sed 's/^/    | /'
    if echo "$out" | grep -q "INTERNAL Error"; then
        echo "    XXX INTERNAL Error crash (the bug)"
        fails=$((fails + 1))
    elif echo "$out" | grep -q "Parser Error" && echo "$out" | grep -q "$expect"; then
        echo "    OK clean Parser Error"
    else
        echo "    XXX unexpected result"
        fails=$((fails + 1))
    fi
done <<EOF
$CASES
EOF

if [ "$fails" -eq 0 ]; then
    echo "repro: PASS - every NULL option yields a clean Parser Error"
    exit 0
fi
echo "repro: FAIL - $fails case(s) did not yield a clean Parser Error"
exit 1
REPRO
chmod +x /app/repro.sh

# 5) prove both directions
bash /app/repro.sh "$PREFIX" > /tmp/oracle_prefix.log 2>&1
rcp=$?
if [ "$rcp" -eq 0 ]; then
    echo "oracle: repro did NOT fail on the pre-fix tree (exit $rcp)" >&2
    tail -12 /tmp/oracle_prefix.log >&2
    exit 1
fi
echo "oracle: repro fails on the pre-fix tree as expected (exit $rcp)"

bash /app/repro.sh /app/src > /tmp/oracle_fixed.log 2>&1
rcf=$?
if [ "$rcf" -ne 0 ]; then
    echo "oracle: repro FAILED on the fixed tree (exit $rcf)" >&2
    tail -20 /tmp/oracle_fixed.log >&2
    exit 1
fi
echo "oracle: repro passes on the fixed tree"

# 6) the tree must contain exactly the one source-file change
status=$(git status --porcelain)
if [ "$status" != " M src/parser/peg/transformer/transform_create_sequence.cpp" ]; then
    echo "oracle: tree not clean besides the fix; status:" >&2
    echo "$status" >&2
    exit 1
fi

# 7) prove nothing else broke: whole sequence regression directory
if ! ( cd /app/src && ./build/release/test/unittest "test/sql/catalog/sequence/*" > /tmp/oracle_suite.log 2>&1 ); then
    echo "oracle: sequence suite did not pass; tail:" >&2
    tail -30 /tmp/oracle_suite.log >&2
    exit 1
fi
grep -E "All tests passed" /tmp/oracle_suite.log | tail -2

cat > /app/summary.md <<'MD'
# sill-barquentine - fix summary

## Symptom

`CREATE SEQUENCE` with `NULL` as the value of any numeric option - `START
[WITH]`, `MINVALUE`, `MAXVALUE` or `INCREMENT [BY]` - crashed the server
instead of rejecting the statement: it printed

    INTERNAL Error: Calling GetValue on a value that is NULL

labelled as an assertion failure, followed by a C++ stack trace. A user
passing NULL from a parameterised or scripted statement got an unhandled
internal error rather than a readable message.

## Root cause

The parser transformer that turns parsed `CREATE SEQUENCE` options into the
statement's typed option values read each option value with
`Value::GetValue<T>()` unconditionally. `GetValue` asserts that the value is
not NULL, so a NULL option value raised the internal assertion during
transformation - before any normal validation could run - and produced the
INTERNAL Error / stack trace.

## Fix

The transformer now checks `value.IsNull()` for each numeric sequence option
before converting it, and rejects a NULL with a descriptive
`ParserException` naming the option: `INCREMENT must not be NULL`,
`MINVALUE must not be NULL`, `MAXVALUE must not be NULL`,
`START value must not be NULL`. Valid numeric options are untouched, so
ordinary `CREATE SEQUENCE` statements behave exactly as before.

## Verification

- `/app/repro.sh` (runs the repository's own CLI over all four NULL paths,
  plus a composed statement) FAILS on the pre-fix code - it sees the
  INTERNAL Error crash - and PASSES on the fixed tree, where every case is a
  clean Parser Error.
- The project's own sequence regression suite
  (`./build/release/test/unittest "test/sql/catalog/sequence/*"`) passes on
  the fixed tree.
MD
test -s /app/summary.md || { echo "oracle: summary.md missing" >&2; exit 1; }

echo "oracle: done"
exit 0