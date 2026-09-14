#!/bin/bash
# Oracle for skiff-beacon: applies the minimal upstream fix to the falcon
# checkout at /app/src (falcon/cyutil/uri.pyx: a literal '+' must never fall
# through to the percent-decoding branch; it is copied through as-is unless
# unquote_plus is enabled, in which case it becomes a space), writes the
# /app/repro.py deliverable, rebuilds the in-place compiled extension, and
# runs the upstream regression test selection against the repaired tree.
set -e

python3 /solution/apply_fix.py /app/src/falcon/cyutil/uri.pyx
cp /solution/repro.py /app/repro.py
chmod 0644 /app/repro.py

echo "== rebuilding the compiled extension from the repaired tree =="
cd /app/src && python3 setup.py build_ext --inplace

echo "== upstream regression selection on the repaired tree =="
cd /app/src && PYTHONPATH=/app/src python3 -m pytest -q \
    /opt/golden/test_utils.py -k uri_decode_unquote_plus

echo "== /app/repro.py against the repaired tree =="
cd /tmp && PYTHONPATH=/app/src python3 /app/repro.py