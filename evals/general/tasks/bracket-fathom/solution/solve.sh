#!/bin/bash
# Oracle for bracket-fathom: applies the upstream duplicate-column fix to the
# real checkout at /app/src, refreshes the installed copy from the repaired
# tree (exactly what the verifier does), and sanity-checks the reproduction
# and the upstream regression test.
set -e

python3 /solution/fix_rows.py /app/src/psycopg/psycopg/rows.py

echo "== refresh the installed copy from the repaired tree =="
python3 -m pip install --force-reinstall --no-deps --no-build-isolation --no-index \
    --root-user-action=ignore /app/src/psycopg

echo "== probe after the fix =="
(cd /tmp && python3 /app/probe_row_factory.py)

echo "== upstream regression test (from /opt/golden) =="
(cd /tmp && python3 -m pytest /opt/golden/test_rows.py::test_make_nt_duplicate_names -q)
