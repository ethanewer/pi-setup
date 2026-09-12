#!/bin/bash
# Oracle for bracket-flint: applies the comma-terminated-argnames fix to the
# pytest checkout at /app/src, then sanity-checks the reproduction and the
# upstream regression tests that were extracted into /opt/golden/ at image
# build time.
set -e

python3 /solution/fix_structures.py

echo "== probe output after the fix =="
cd /app/src
python3 -m pytest /app/test_parametrize_comma.py -q -p no:cacheprovider

echo "== upstream regression tests (golden) =="
META=/app/src/testing/python/metafunc.py
cp "$META" /tmp/metafunc.py.orig
restore() { cp /tmp/metafunc.py.orig "$META"; }
trap restore EXIT
cp /opt/golden/metafunc.py "$META"
python3 -m pytest \
  "testing/python/metafunc.py::TestMetafunc::test_parametrize_single_arg_trailing_comma" \
  "testing/python/metafunc.py::TestMetafuncFunctional::test_parametrize_single_arg_trailing_comma_functional" \
  -q -p no:cacheprovider
trap - EXIT
restore
rm -f /tmp/metafunc.py.orig
echo "oracle done"