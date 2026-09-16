#!/bin/bash
# Oracle for oakum-landfall: applies the real two-file fix to the pinned
# setuptools tree at /app/src (the shared name-normalisation helper
# 'safer_name' implements the canonical normalisation rule -- collapse runs
# of [-_.] to '-', lowercase, replace '-' with '_' -- and the bdist_wheel
# command drops its private duplicate helpers and imports the shared one,
# so BOTH code paths that build distribution-name filename components emit
# the canonical form), writes /app/reproduce.py, then proves the work: the
# reproduction passes against the repaired tree, and the project's own
# regression tests and the surrounding wheel tests pass. Reads only /app,
# /solution and /opt, never /tests.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch
echo "oracle: applied the canonical wheel-name normalisation fix"

cp /solution/reproduce.py /app/reproduce.py
chmod 644 /app/reproduce.py

if ! python3 /app/reproduce.py > /tmp/oracle-repro.log 2>&1; then
    echo "oracle: reproduction failed against the repaired tree; tail:" >&2
    tail -20 /tmp/oracle-repro.log >&2
    exit 1
fi
cat /tmp/oracle-repro.log

# Run the project's OWN golden regression tests from the tree (never the
# graded /tests mount). cwd stays /app/src, NOT the package dir: running
# from inside setuptools/ would put /app/src/setuptools first on sys.path
# and shadow the stdlib 'logging' module with the tree's own logging.py.
cd /app/src
TT="tests"
if ! python3 -m pytest -q \
        "setuptools/$TT/test_bdist_wheel.py::test_unicode_record" \
        "setuptools/$TT/test_dist_info.py::TestWheelCompatibility" \
        > /tmp/oracle-golden.log 2>&1; then
    echo "oracle: golden regression tests failed; tail:" >&2
    tail -20 /tmp/oracle-golden.log >&2
    exit 1
fi
tail -2 /tmp/oracle-golden.log

echo "oracle: all checks passed"