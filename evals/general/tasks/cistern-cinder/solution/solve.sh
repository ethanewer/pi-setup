#!/bin/bash
# Oracle for cistern-cinder: applies the fix to the psutil checkout at
# /app/src (parse each /proc/meminfo line on the first ':' and take the first
# whitespace-separated token of the value), then re-runs the probe and the
# upstream regression test that was extracted into /opt/golden/ at image
# build time. Pure-Python change; the editable install picks it up directly.
set -e

cd /app/src
git apply --whitespace=nowarn /solution/fix.patch

echo "== probe output after the fix =="
python3 /app/probe_meminfo.py

echo "== upstream regression test =="
python3 -m pytest \
    tests/test_linux.py::TestVirtualMemoryMocks::test_virtual_memory_no_space_after_colon \
    -q -p no:cacheprovider