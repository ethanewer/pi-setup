#!/bin/bash
# Oracle for galiot-cinder. Writes the reproduction deliverable
# /app/reproduce_bug.py, applies the minimal upstream fix to
# falcon/testing/helpers.py in the checkout at /app/src, and proves the
# repaired tree: the reproduction exits 0, the project's own regression test
# for the RAW_URI defect (at /opt/golden, extracted from the fix commit at
# image build time) passes, and the whole tests/test_testing.py module still
# passes (nothing else broke).
set -e

cp /solution/reproduce_bug.py /app/reproduce_bug.py
python3 /solution/fix_helpers.py /app/src

echo "== reproduction against repaired tree =="
python3 /app/reproduce_bug.py

echo "== project's own regression test (from /opt/golden) =="
cd /app/src
python3 -m pytest /opt/golden/test_preserve_raw_uri.py -q -p no:cacheprovider

echo "== project's own suite: tests/test_testing.py =="
python3 -m pytest tests/test_testing.py -q -p no:cacheprovider