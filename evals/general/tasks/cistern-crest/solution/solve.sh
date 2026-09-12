#!/bin/bash
# Oracle for cistern-crest: applies the _mtime_meta fix to the gallery-dl
# checkout (/app/src), sanity-checks the reproduction, and runs the upstream
# regression tests extracted into /opt/golden/ at image build time, plus the
# project's own postprocessor suite (excluding the mtime tests, whose in-tree
# expectations encode the buggy behaviour).
set -e

python3 /solution/fix_mtime.py /app/src/gallery_dl/postprocessor/mtime.py

echo "== probe output after the fix =="
cd /app
python3 probe_mtime.py

echo "== upstream regression tests =="
cd /app/src
python3 -m pytest /opt/golden/test_postprocessor.py::MtimeTest -q -p no:cacheprovider

echo "== project's own postprocessor suite (excluding mtime tests) =="
python3 -m pytest test/test_postprocessor.py -k "not mtime" -q -p no:cacheprovider