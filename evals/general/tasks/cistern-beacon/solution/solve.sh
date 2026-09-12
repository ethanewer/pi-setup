#!/bin/bash
# Oracle for cistern-beacon: applies sympy's one-line linprog no-constraints
# fix to the checkout (/app/src), sanity-checks the reproduction with the
# shipped probe, and runs the upstream regression test extracted into
# /opt/golden/ at image build time.
set -e

python3 /solution/fix_linprog.py /app/src/sympy/solvers/simplex.py

echo "== probe output after the fix =="
python3 /app/probe_linprog.py

echo "== upstream regression test =="
cd /app/src
python3 -m pytest /opt/golden/test_simplex.py::test_29368 -c /app/src/pyproject.toml -q -p no:cacheprovider