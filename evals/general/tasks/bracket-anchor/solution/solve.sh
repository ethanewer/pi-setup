#!/bin/bash
# Oracle for bracket-anchor: applies the RFC 6265 ASCII-only cookie-expiry fix
# to the aiohttp checkout (/app/src), sanity-checks the reproduction, and runs
# the upstream regression test extracted into /opt/golden/ at image build time.
set -e

python3 /solution/fix_cookiejar.py /app/src/aiohttp/cookiejar.py

echo "== probe output after the fix =="
python3 /app/probe_cookie_jar.py

echo "== upstream regression test =="
cd /app/src
python3 -m pytest /opt/golden/test_cookiejar.py::test_date_parsing -q -p no:cacheprovider