#!/bin/bash
# Oracle for kedge-fairway: applies the minimal fix to the gallery-dl checkout
# (/app/src), installs the reproduction deliverable (/app/reproduce.py),
# and sanity-checks the repaired tree with the reproduction, the upstream
# regression test extracted into /opt/golden at build time, and the project's
# own downloader suite.  Hidden cases are exercised by the verifier.
set -e

python3 /solution/fix_http.py /app/src/gallery_dl/downloader/http.py
cp /solution/reproduce.py /app/reproduce.py

echo "== reproduction against the repaired tree =="
cd /tmp
python3 /app/reproduce.py

echo "== upstream regression test (fix-commit downloader test file) =="
cd /app/src
python3 -m pytest /opt/golden/test_downloader.py -q -p no:cacheprovider

echo "== project's own downloader suite =="
python3 -m pytest test/test_downloader.py -q -p no:cacheprovider