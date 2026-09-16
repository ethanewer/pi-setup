#!/bin/bash
# Oracle for bracket-compass: applies the required-block body check fix to the
# jinja checkout (/app/src), sanity-checks the reproduction, and runs the
# upstream regression test extracted into /opt/golden/ at image build time.
set -e

python3 /solution/fix_parser.py /app/src/src/jinja2/parser.py

echo "== probe output after the fix =="
python3 /app/probe_required_block.py

echo "== upstream regression test =="
cd /app/src
python3 -m pytest /opt/golden/test_inheritance.py::TestInheritance::test_invalid_required -q -p no:cacheprovider