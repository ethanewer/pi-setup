#!/bin/bash
# Oracle for mooring-port: applies the upstream fix (the empty-tuple guard in
# pylint/extensions/typing.py), installs the reproduction deliverable, re-runs
# the reproduction, and runs the upstream regression test extracted into
# /opt/golden/ at image build time plus the typing-extension functional suite.
set -e

python3 /solution/fix_typing.py

cp /solution/reproduce.py /app/reproduce.py
chmod a+rx /app/reproduce.py

echo "== reproduction output after the fix =="
cd /app/src
python3 /app/reproduce.py

echo "== upstream regression test for this behaviour =="
cp /opt/golden/ext/typing/unnecessary_default_type_args.py tests/functional/ext/typing/
python3 -m pytest tests/test_functional.py -k unnecessary_default_type_args \
  -o addopts="" -q -p no:cacheprovider
# restore the tree: the golden file is the fix-commit version of the test and
# must not remain overlaid (the verifier re-applies it itself)
git checkout -q -- tests/functional/ext/typing/

echo "== typing-extension functional tests =="
python3 -m pytest tests/test_functional.py -k "typing or redundant_typehint" \
  -o addopts="" -q -p no:cacheprovider

echo "== oracle done =="