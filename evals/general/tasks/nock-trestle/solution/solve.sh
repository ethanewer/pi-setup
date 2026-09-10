#!/bin/bash
# Oracle for nock-trestle: repairs the seeded regression in the Trino SQL
# parser (interval year/month field mapping), proves the module's own test
# suite green, and writes the /app/fix-summary.md deliverable.
#
# The oracle works like the agent: the module's own tests are the bug report.
# It runs the failing subset, identifies the interval-unit surface, restores
# the correct field mapping in the parser sources, re-runs the full module
# suite, and only then writes the deliverable. It never reads /tests.
set -euo pipefail

SRC=/app/src
MVN=(mvn -B -o -f core/trino-parser/pom.xml \
    -Dmaven.source.skip=true -Dair.check.skip-all=true -Dmaven.javadoc.skip=true)

cd "$SRC"

# 1) Reproduce the failure the acceptance defines (before-fix evidence).
"${MVN[@]}" -Dtest=TestTypeParser -Dsurefire.failIfNoSpecifiedTests=false test \
    > /tmp/oracle-before.log 2>&1 || true
grep -E "testInverval|Tests run:" /tmp/oracle-before.log | head -4

# 2) Fix the root cause in the parser main sources.
python3 /solution/fix_interval_units.py "$SRC"

# 3) Prove the fix: the full trino-parser module suite must exit 0.
"${MVN[@]}" test

# 4) Deliverable: the diagnosis.
cat > /app/fix-summary.md <<'MD'
# Regression fix: Trino SQL parser interval units

## Symptom

The module's own test suite fails in four places. The type parser reports
`INTERVAL YEAR(1)` with a MONTH field and `INTERVAL MONTH(1)` with a YEAR
field; the same swapped units appear in interval literals (`INTERVAL '123'
YEAR`), in the expression formatter output, and in the TPC-H statement
builder test.

## Root cause

One switch in the parser's AST builder
(`core/trino-parser/src/main/java/io/trino/sql/parser/AstBuilder.java`,
`visitSimpleYearMonthInterval`) had its YEAR and MONTH arms swapped, so the
simple interval qualifiers `INTERVAL YEAR` and `INTERVAL MONTH` built the
wrong interval field. Composite qualifiers (`YEAR TO MONTH`) were unaffected,
which is why only some tests failed.

## Fix

Swapped the two arms back so that the YEAR token produces an
`IntervalField.Year()` and the MONTH token produces an
`IntervalField.Month()`. With that one-line-equivalent repair the full
`core/trino-parser` module test suite passes.
MD

# 5) Sanity (non-fatal): the deliverable exists and the fix left a diff.
[ -s /app/fix-summary.md ] || { echo "WARN: fix-summary.md missing" >&2; exit 1; }
git -C "$SRC" status --porcelain | grep -q "core/trino-parser/src/main/" \
    || echo "WARN: no src/main diff visible in git status"

echo "nock-trestle oracle done"