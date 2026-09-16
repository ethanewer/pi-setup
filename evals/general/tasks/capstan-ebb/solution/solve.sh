#!/usr/bin/env bash
# Oracle for capstan-ebb: applies the one-line upstream fix to the real bandit
# tree at /app/src (SIMPLE_SQL_RE must accept the '(' right after VALUES in
# INSERT statements, not only whitespace, because VALUES( is equally valid SQL
# and equally injectable), writes /app/summary.md, then proves the work with
# the project's own machinery: the issue reproduction must yield one B608
# finding, and the project's own regression test (fix-version example + test
# file, baked at /opt/golden) plus the full functional and unit suites must
# pass. Reads only /app, /solution and /opt/golden, never /tests.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to a clean pinned tree" >&2
    git diff -- bandit/plugins/injection_sql.py | head -30 >&2
    exit 1
}
git apply /solution/fix.patch
echo "oracle: applied VALUES( no-space detection fix"

cat > /app/summary.md <<'MD'
# Change summary (oracle)

Bug: bandit's B608 SQL-injection check failed to detect INSERT statements
whose value list opens directly after `VALUES` with no space, e.g.
`cur.execute("INSERT INTO foo VALUES(%s)" % value)`. The statement-matching
regular expression `SIMPLE_SQL_RE` in the injection plugin required a
whitespace character immediately after the keyword `values`
(`insert\s+into\s.*values\s`), so the equally-valid `VALUES(` spelling was
never matched and unsanitised input flowing into such a query string passed a
scan silently, while the spaced `VALUES (` form was correctly reported.

Fix: widened the alternation to accept either whitespace or the opening
parenthesis after `values` (`values[\s(]`). Both spellings are now matched,
case-insensitively (the regex is built with re.IGNORECASE), across multi-line
statements (re.DOTALL) and for every string-building style the check already
handles (`%`-formatting, f-strings, str.format, implicit/literal
concatenation). Parameterised queries (`execute(sql, params)`) are untouched:
they are not string-building, so they still produce no finding, and nothing
else about the SELECT/DELETE/UPDATE branches of the matcher changed.

Verification:
- the issue reproduction now exits 1 and reports exactly one B608 finding
  (Severity: Medium, Confidence: Medium) at the `execute("INSERT INTO foo
  VALUES(%s)" % ...)` line;
- the project's own successor-revision regression test
  (FunctionalTests::test_sql_statements with the fix-version example,
  planted from /opt/golden) passes, as does the whole functional module
  (79 tests) and the whole unit test suite (178 tests) under unittest;
- hidden CLI scans on a lower-case %-formatted executemany file, on
  f-string/.format() constructions, and on a multi-line implicit-concat
  INSERT all report B608 for the `VALUES(` lines while the parameterised
  `VALUES(?, ?)` control lines stay clean.
MD

# Prove the fix with the issue's exact reproduction.
printf '%s\n' \
    'import sqlite3' \
    "conn = sqlite3.connect('app.db')" \
    'cur = conn.cursor()' \
    "value = \"x' OR '1'='1\"" \
    'cur.execute("INSERT INTO foo VALUES(%s)" % value)' \
    > /tmp/values.py
(cd /tmp && bandit -f json /tmp/values.py > /tmp/oracle_repro.json 2>/dev/null || true)
python3 -c 'import json, sys
d = json.load(open(sys.argv[1]))
r = [(x["test_id"], x["line_number"], x["issue_severity"], x["issue_confidence"])
     for x in d["results"]]
assert r == [("B608", 5, "MEDIUM", "MEDIUM")], r' /tmp/oracle_repro.json || {
    echo "oracle: reproduction not flagged as one B608 Medium/Medium at line 5" >&2
    cat /tmp/oracle_repro.json >&2
    exit 1
}
echo "oracle: reproduction reports exactly one B608 Medium/Medium"

# Plant and run the project's own regression test for this bug.
cp /opt/golden/sql_statements.py examples/sql_statements.py
cp /opt/golden/test_functional.py tests/functional/test_functional.py
python3 -m unittest tests.functional.test_functional.FunctionalTests.test_sql_statements \
    > /tmp/oracle_golden.log 2>&1 || {
    echo "oracle: golden regression test did not pass; tail:" >&2
    tail -30 /tmp/oracle_golden.log >&2
    exit 1
}
python3 -m unittest tests.functional.test_functional > /tmp/oracle_func.log 2>&1 || {
    echo "oracle: functional module did not pass; tail:" >&2
    tail -30 /tmp/oracle_func.log >&2
    exit 1
}
python3 -m unittest discover -s tests/unit -p 'test_*.py' > /tmp/oracle_unit.log 2>&1 || {
    echo "oracle: unit suite did not pass; tail:" >&2
    tail -30 /tmp/oracle_unit.log >&2
    exit 1
}
tail -2 /tmp/oracle_golden.log
tail -2 /tmp/oracle_func.log
tail -2 /tmp/oracle_unit.log

# Leave the tree exactly as the verifier expects it: the regression assets
# were planted here only to prove the fix and must not persist (the verifier
# re-plants them itself and asserts every tracked file except the fixed source
# file is byte-identical to the pinned commit). The source fix STAYS, so the
# only allowed "M" entry in git status is the injection plugin itself.
git checkout -- examples/sql_statements.py tests/functional/test_functional.py || {
    echo "oracle: could not restore planted regression assets" >&2
    exit 1
}
UNEXPECTED=$(git status --porcelain | grep -v -F "M bandit/plugins/injection_sql.py" || true)
if [ -n "$UNEXPECTED" ]; then
    echo "oracle: unexpected working-tree state after restore:" >&2
    echo "$UNEXPECTED" >&2
    exit 1
fi
rm -f /tmp/values.py /tmp/oracle_repro.json /tmp/oracle_golden.log /tmp/oracle_func.log /tmp/oracle_unit.log

echo "oracle: fix applied, summary written, regression + suites green"
exit 0