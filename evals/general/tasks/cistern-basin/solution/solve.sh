#!/bin/bash
# Oracle for cistern-basin: applies the comma-separated SQLite table-option
# DDL fix to the SQLAlchemy checkout (/app/src), sanity-checks the
# reproduction, and runs the project's own upstream regression test for the
# bug, extracted at image build time into /opt/golden/.  The golden file is
# the fix commit's test/dialect/test_sqlite.py, so it must be run with the
# project's testing plugin and rootdir, exactly as the verifier does.
set -e

python3 /solution/fix_post_create_table.py \
    /app/src/lib/sqlalchemy/dialects/sqlite/base.py

echo "== probe output after the fix =="
python3 /app/probe_ddl.py

echo "== upstream regression test =="
cd /app/src
python3 -m pytest \
    /opt/golden/test_sqlite.py::SQLTest::test_create_table_without_rowid_strict \
    -q -p no:cacheprovider \
    -p sqlalchemy.testing.plugin.pytestplugin --rootdir=/app/src