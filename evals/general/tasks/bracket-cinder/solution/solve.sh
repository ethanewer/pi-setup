#!/bin/bash
# Oracle for bracket-cinder: applies the fix to the gallery-dl checkout at
# /app/src (wrap per-field results in str() whenever a non-default fmt is
# passed and the template has multiple parts), then sanity-checks the
# reproduction and runs the upstream regression test that was extracted into
# /opt/golden/ at image build time.
set -e

cd /app/src
git apply --whitespace=nowarn /solution/formatter.patch

echo "== probe output after the fix =="
python3 /app/probe_fmt.py

echo "== upstream regression test =="
python3 -m pytest /opt/golden/test_formatter.py::TestFormatter::test_fmt_func_multi \
    -q -p no:cacheprovider