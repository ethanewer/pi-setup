#!/bin/bash
# Oracle for ballast-quay: applies the mixed raw/non-raw implicit-str-concat
# fix to the pylint checkout (/app/src), re-runs the reproduction probe, and
# runs the upstream regression test extracted into /opt/golden/ at image build
# time.
set -e

SRC=/app/src
GOLDEN_DIR=tests/functional/i/implicit

python3 /solution/fix_strings.py "$SRC/pylint/checkers/strings.py"

echo "== reproduction probe after the fix =="
python3 /app/probe.py

echo "== upstream regression test (golden files from the fix commit) =="
cd "$SRC"
cp "$GOLDEN_DIR/implicit_str_concat.py" /tmp/orig_isc.py
cp "$GOLDEN_DIR/implicit_str_concat.txt" /tmp/orig_isc.txt
cp /opt/golden/implicit_str_concat.py "$GOLDEN_DIR/implicit_str_concat.py"
cp /opt/golden/implicit_str_concat.txt "$GOLDEN_DIR/implicit_str_concat.txt"
python3 -m pytest tests/test_functional.py -k implicit_str_concat -q -p no:cacheprovider
rc=$?
cp /tmp/orig_isc.py "$GOLDEN_DIR/implicit_str_concat.py"
cp /tmp/orig_isc.txt "$GOLDEN_DIR/implicit_str_concat.txt"
exit $rc