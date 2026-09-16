#!/bin/bash
# Oracle for ballast-boom: applies the escaped-brace f-string redaction fix
# to the flake8 checkout (/app/src), re-runs the reproduction, and runs the
# upstream regression test extracted into /opt/golden/ at image build time.
set -e

python3 /solution/fix_processor.py /app/src/src/flake8/processor.py

echo "== reproduction output after the fix =="
python3 /app/probe_fstring_redaction.py

echo "== upstream regression test =="
cd /app/src
# Run the upstream regression test straight from /opt/golden/: the golden file
# is the fix-commit version of tests/integration/test_plugins.py kept out of
# the working tree, so the oracle leaves the tree with only the fix applied.
python3 -m pytest "/opt/golden/test_plugins.py::test_escaping_of_fstrings_in_string_redacter" \
  -o addopts="" -q -p no:cacheprovider

echo "== oracle done =="