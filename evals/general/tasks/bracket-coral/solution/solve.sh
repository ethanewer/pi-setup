#!/bin/bash
# Oracle for bracket-coral: applies the minimal upstream fix for the multipart
# boundary-newline corruption to the werkzeug checkout at /app/src, then proves
# it with the probe and the project's own regression test .
set -e

python3 /solution/fix_multipart.py

echo "== probe after the fix =="
python3 /app/probe_upload_corruption.py

echo "== upstream regression test for this bug =="
cd /app/src
python3 -m pytest /opt/golden/test_multipart.py -q -p no:cacheprovider

echo "== the tree's own multipart-adjacent tests =="
python3 -m pytest tests/sansio/test_multipart.py tests/test_formparser.py tests/test_wrappers.py -q -p no:cacheprovider