#!/bin/bash
# Oracle for reef-sail: applies the SQLite CHECK-constraint reflection fix
# to the SQLAlchemy checkout (/app/src), drops the reproduction deliverable
# in place, shows it passing on the repaired tree, and runs the upstream
# regression tests extracted at image build time into /opt/golden/.
set -e

echo "== apply fix =="
python3 /solution/fix_check_constraints.py \
    /app/src/lib/sqlalchemy/dialects/sqlite/base.py

echo "== deliverables =="
cp /solution/reproduce_check_constraints.py /app/reproduce_check_constraints.py
ls -l /app/reproduce_check_constraints.py

echo "== reproduction on the repaired tree (must exit 0) =="
cd /app/src
python3 /app/reproduce_check_constraints.py

echo "== upstream regression tests (ConstraintReflectionTest from /opt/golden) =="
python3 -m pytest \
    /opt/golden/test_sqlite.py::ConstraintReflectionTest \
    -q -p no:cacheprovider \
    -p sqlalchemy.testing.plugin.pytestplugin --rootdir=/app/src