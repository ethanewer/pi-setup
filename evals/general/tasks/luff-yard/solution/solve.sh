#!/bin/bash
# Oracle for luff-yard: applies the WWW-Authenticate trailing-space fix to
# the werkzeug checkout (/app/src), writes the reproduction deliverable
# (/app/reproduce_www_authenticate_bug.py), then proves the reproduction and
# the project's own regression test (extracted into /opt/golden/ at image
# build time, fix-commit version of tests/test_http.py) both pass.
set -e

python3 /solution/solver.py

echo "== reproduction after the fix =="
python3 /app/reproduce_www_authenticate_bug.py

echo "== upstream regression test (from /opt/golden) =="
cd /app/src
cp /opt/golden/test_http.py tests/test_http.py
python3 -m pytest "tests/test_http.py::TestHTTPUtility::test_www_authenticate_header" \
  -o addopts="" -q -p no:cacheprovider
python3 -m pytest tests/test_http.py -o addopts="" -q -p no:cacheprovider
git checkout -- tests/test_http.py

echo "== project's own suites =="
python3 -m pytest tests/test_http.py tests/test_datastructures.py \
  -o addopts="" -q -p no:cacheprovider

echo "== oracle done =="