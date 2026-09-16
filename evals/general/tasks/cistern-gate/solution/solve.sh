#!/bin/bash
# Oracle for cistern-gate: applies the InvalidMarker -> InstallationError fix
# to the pip checkout (/app/src), re-runs the reproduction, and runs the
# upstream regression test extracted into /opt/golden/ at image build time.
set -e

python3 /solution/fix_constructors.py /app/src/src/pip/_internal/req/constructors.py

echo "== reproduction output after the fix =="
python3 /app/probe_invalid_marker.py

echo "== upstream regression test =="
cd /app/src
python3 -m pytest /opt/golden/test_req.py::TestInstallRequirement::test_markers_invalid \
  -o addopts="" -q -p no:cacheprovider