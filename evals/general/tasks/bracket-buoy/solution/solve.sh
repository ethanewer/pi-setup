#!/bin/bash
# Oracle for bracket-buoy: applies the upstream fix (a /32 or /128
# single-host network has no broadcast address) to the psutil checkout at
# /app/src, then proves it with the probe, an assertion suite that mirrors
# the project's upstream regression test, and the project's own test slice.
set -e

python3 /solution/fix_broadcast.py

echo "== probe output after the fix =="
python3 /app/probe_netinfo.py

echo "== functional contract checks (mirror the upstream regression test) =="
cd /app/src
python3 -m pytest /solution/verify_fix.py -q -p no:cacheprovider

echo "== project's own misc tests (excl. setup.py subprocess tests) =="
python3 -m pytest tests/test_misc.py -k "not TestSetupPy" \
  -q -p no:cacheprovider

echo "== project's own net_if_addrs / net_if_stats tests =="
python3 -m pytest tests/test_system.py -k "net_if_addrs or net_if_stats" \
  -q -p no:cacheprovider

echo "== porcelain after the fix =="
git -C /app/src status --porcelain