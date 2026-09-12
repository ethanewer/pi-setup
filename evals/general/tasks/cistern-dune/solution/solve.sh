#!/bin/bash
# Oracle for cistern-dune: applies the FuncParamType ValueError-message fix to
# the click checkout (/app/src), sanity-checks the reproduction, and runs the
# upstream regression test extracted into /opt/golden/ at image build time.
set -e

echo "== probe output before the fix =="
python3 /app/probe_func_param_type.py

python3 /solution/fix_func_param_type.py /app/src/src/click/types.py

echo "== probe output after the fix =="
python3 /app/probe_func_param_type.py

echo "== upstream regression test =="
cd /app/src
python3 -m pytest /opt/golden/test_types.py::test_func_param_type_uses_value_error_message \
  -c pyproject.toml -q -p no:cacheprovider

echo "== project's own types tests =="
python3 -m pytest tests/test_types.py -c pyproject.toml -q -p no:cacheprovider