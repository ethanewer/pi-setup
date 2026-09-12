#!/bin/bash
# Oracle for bracket-ember: applies the JSONDecodeError pickling fix to the
# requests checkout (/app/src), sanity-checks the reproduction, and runs the
# upstream regression test extracted into /opt/golden/ at image build time.
set -e

python3 /solution/fix_exceptions.py /app/src/src/requests/exceptions.py

echo "== probe output after the fix =="
python3 /app/probe_json_pickle.py

echo "== upstream regression test =="
cd /opt/golden
python3 -m pytest tests/test_requests.py::test_json_decode_errors_are_serializable_deserializable \
  -q -p no:cacheprovider