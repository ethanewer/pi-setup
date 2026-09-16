#!/bin/bash
# Oracle for bracket-cleat: applies the upstream fix (an option declared
# is_flag=False with flag_value and default is allowed to be used without a
# value, falling back to the flag_value) to the click checkout at /app/src,
# then proves the fix with the probe, the upstream regression tests, and the
# project's own option/argument/basic suites.
set -e

python3 /solution/fix_core.py

echo "== probe output after the fix =="
python3 /app/probe_flag_value.py

echo "== upstream regression tests (golden) =="
cd /app/src
python3 -m pytest \
  "/opt/golden/test_options.py::test_flag_value_optional_behavior" \
  "/opt/golden/test_options.py::test_flag_value_with_type_conversion" \
  -q -p no:cacheprovider

echo "== project's own suites =="
python3 -m pytest tests/test_options.py tests/test_arguments.py tests/test_basic.py -q -p no:cacheprovider