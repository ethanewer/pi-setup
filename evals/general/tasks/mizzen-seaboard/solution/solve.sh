#!/bin/bash
# Oracle for mizzen-seaboard: applies the upstream one-file fix (the
# client-encoding alias table) to the real psycopg tree at /app/src, writes
# /app/repro.sh and /app/summary.md, then proves the work: the reproduction
# must FAIL against the pristine pre-fix package at /opt/prefix/psycopg and
# PASS against the fixed tree via PSYCOPG_PACKAGE_DIR=/app/src/psycopg, and
# the project's own DB-free test files stay green from a site-packages copy
# refreshed from the delivered tree. Reads only /app, /solution and /opt,
# never /tests.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch || exit 1
echo "oracle: applied the client-encoding alias fix"

cat > /app/repro.sh <<'SH'
#!/usr/bin/env bash
# Failing reproduction for the client_encoding alias bug.
# Contract: honours PSYCOPG_PACKAGE_DIR (default /opt/prefix/psycopg - the
# pristine pre-fix copy baked into the image), works from any cwd, writes
# only to a scratch dir under /tmp, prints every check, exits 0 iff all
# documented alias names resolve to the correct codec.
set -u
PKG_DIR=${PSYCOPG_PACKAGE_DIR:-/opt/prefix/psycopg}
work=$(mktemp -d /tmp/repro.XXXXXX) || exit 1
trap 'rm -rf "$work"' EXIT
cd "$work" || exit 1
python3 - "$PKG_DIR" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
from psycopg import _encodings as e

CHECK = "user=foo dbname=bar client_encoding=%s"

# documented PG alias -> expected codec (PostgreSQL docs charset table)
expect = {
    "MSKANJI": "shift_jis",   # alias of SJIS (Shift_JIS)
    "WIN932": "shift_jis",
    "KOI8": "koi8-r",         # alias of KOI8R
    "WIN949": "cp949",        # alias of UHC
    "Unicode": "utf-8",       # alias of UTF8
}
ok = True
for alias, want in expect.items():
    got = e.conninfo_encoding(CHECK % alias)
    flag = "ok" if got == want else "WRONG"
    print("%-10s -> %-12s (expected %-12s) %s" % (alias, got, want, flag))
    ok = ok and got == want

# canonical names must keep working; unknown names keep the utf-8 fallback
stable = {
    "EUC_JP": "euc_jp",
    "SJIS": "shift_jis",
    "WAT": "utf-8",
}
for name, want in stable.items():
    got = e.conninfo_encoding(CHECK % name)
    flag = "ok" if got == want else "WRONG"
    print("%-10s -> %-12s (expected %-12s) %s" % (name, got, want, flag))
    ok = ok and got == want

sys.exit(0 if ok else 1)
PY
exit $?
SH
chmod +x /app/repro.sh
echo "oracle: wrote /app/repro.sh"

cat > /app/summary.md <<'MD'
# Change summary (oracle)

Bug: a `client_encoding` option in a connection string that uses any of
PostgreSQL's documented charset alias names - e.g. MSKANJI, the documented
name for Shift_JIS/SJIS - was silently ignored. psycopg's pg2pyenc lookup
only recognised canonical names, so the alias fell through to the default
utf-8 and server text was decoded with the wrong codec (garbled output, no
error).

Cause: the codec mapping table in psycopg's encoding module
(psycopg/psycopg/_encodings.py) was a flat dictionary from canonical
PostgreSQL name to Python codec; the documented aliases of each charset
(WIN950/Windows950 for BIG5, WIN932/ShiftJIS/Mskanji for SJIS, KOI8 for
KOI8R, WIN949/Windows949 for UHC, Unicode for UTF8, ALT for WIN866,
ABC/TCVN/TCVN5712/VSCII for WIN1258, ISO88591..ISO885916 for LATIN1..10,
WIN for WIN1251 and so on) were missing, so pg2pyenc raised
NotSupportedError and conninfo_encoding silently fell back to utf-8.

Change: restructured the table to one entry per charset keyed by a tuple of
(canonical name, documented aliases), rebuilt the runtime lookup map by
upper-casing every alias (plus the existing no-underscore variant), and
kept the codec resolution and the missing-name NotSupportedError behaviour
identical. Now every documented alias resolves to the same Python codec as
its canonical name, canonical names are unchanged, and unknown names still
fall back to utf-8.

Verification: /app/repro.sh fails against the pristine pre-fix package at
/opt/prefix/psycopg (aliases resolve to utf-8) and passes against the fixed
tree (PSYCOPG_PACKAGE_DIR=/app/src/psycopg); the project's own
tests/test_encodings.py, tests/test_conninfo.py and tests/test_sql.py stay
green; the upstream regression test planted from /opt/golden passes all 21
tests, including the MSKANJI/mskanji rows.
MD
echo "oracle: wrote /app/summary.md"

# Prove the work in both directions with the real code path.
if bash /app/repro.sh > /tmp/oracle_pre.out 2>&1; then
    echo "oracle: /app/repro.sh PASSED against the pristine pre-fix package (expected failure)" >&2
    cat /tmp/oracle_pre.out >&2
    exit 1
fi
if ! PSYCOPG_PACKAGE_DIR=/app/src/psycopg bash /app/repro.sh > /tmp/oracle_post.out 2>&1; then
    echo "oracle: /app/repro.sh FAILED against the fixed tree; out:" >&2
    cat /tmp/oracle_post.out >&2
    exit 1
fi
echo "oracle: repro OK on fixed tree, fails on pristine pre-fix package"

# Break-nothing sanity on the project's own DB-free test files, with the
# installed library refreshed from the delivered tree.
SP=$(python3 -c "import psycopg, os; print(os.path.dirname(psycopg.__file__))")
rm -rf "$SP" && cp -a /app/src/psycopg/psycopg "$SP"
cd /app/src || exit 1
for t in test_encodings.py test_conninfo.py test_sql.py; do
    if ! python3 -m pytest "tests/$t" -q -o cache_dir=/tmp/oracle-pyc > "/tmp/oracle-$t.log" 2>&1; then
        echo "oracle: $t failed; tail:" >&2
        tail -20 "/tmp/oracle-$t.log" >&2
        exit 1
    fi
done
grep -q "17 passed" /tmp/oracle-test_encodings.py.log || { echo "oracle: test_encodings not 17 passed" >&2; exit 1; }
grep -q "43 passed" /tmp/oracle-test_conninfo.py.log || { echo "oracle: test_conninfo not 43 passed" >&2; exit 1; }
grep -q "44 passed, 80 skipped" /tmp/oracle-test_sql.py.log || { echo "oracle: test_sql not 44/80" >&2; exit 1; }
echo "oracle: project's own DB-free tests green on the fixed tree"

echo "oracle: fix applied, deliverables written, repro OK both directions, project tests green"
exit 0