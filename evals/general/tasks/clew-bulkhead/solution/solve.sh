#!/bin/bash
# Oracle for clew-bulkhead: applies the one-source-file fix to the real
# scipy/spatial/_qhull.pyx in /app/src (the ConvexHull constructor must
# validate that the points array is 2-D before indexing it), rebuilds the
# editable install, writes /app/repro.sh and /app/summary.md, and proves the
# work: the reproduction must pass against the repaired tree and must fail
# against the pristine pre-fix snapshot at /opt/prefix-pylib. Reads only
# /app, /solution and /opt only.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

if ! git apply --check /solution/fix.patch >/dev/null 2>&1; then
    echo "oracle: fix.patch does not apply to a clean pinned tree" >&2
    exit 1
fi
git apply /solution/fix.patch
echo "oracle: applied the ConvexHull ndim-validation fix"

if ! python3 -m pip install -e . --no-build-isolation \
        --config-settings=builddir=/work/sci-build > /tmp/oracle_build.log 2>&1; then
    echo "oracle: incremental rebuild failed; tail:" >&2
    tail -30 /tmp/oracle_build.log >&2
    exit 1
fi
echo "oracle: incremental rebuild ok"

cat > /app/repro.sh <<'SH'
#!/bin/bash
# Failing reproduction for the ConvexHull non-2-D-input crash.
# Contract: exits 0 iff scipy.spatial.ConvexHull rejects a flat 1-D points
# array with a clean catchable ValueError whose message states the input
# must be a 2-D array of shape (npoints, ndim); prints the error message to
# stdout. Exits non-zero for every other outcome (internal IndexError,
# crash, call succeeding, import failure). Runs under the ambient python3
# from any working directory and touches nothing outside /tmp.
set -u
cd /tmp || exit 1
python3 - <<'PY'
import sys

import numpy as np

try:
    from scipy.spatial import ConvexHull
except BaseException as e:
    sys.stderr.write("import of scipy.spatial failed: %s: %s\n" % (type(e).__name__, e))
    sys.exit(4)

try:
    ConvexHull(np.ones(5))  # flat 1-D array: not a matrix of samples
except ValueError as e:
    msg = str(e)
    print("rejected with ValueError:", msg)
    if "shape" in msg:
        sys.exit(0)   # clean, helpful validation error
    sys.stderr.write("ValueError raised but it does not explain the shape problem\n")
    sys.exit(5)
except BaseException as e:
    sys.stderr.write("not a clean ValueError: %s: %s\n" % (type(e).__name__, e))
    sys.exit(6)       # the internal IndexError (pre-fix) lands here
else:
    sys.stderr.write("no error raised\n")
    sys.exit(7)
PY
SH
chmod +x /app/repro.sh
echo "oracle: wrote /app/repro.sh"

cat > /app/summary.md <<'MD'
# Change summary (oracle)

Bug: `scipy.spatial.ConvexHull` did not validate the dimensionality of its
`points` input. A flat 1-D array (e.g. `np.ones(5)`) failed deep inside the
constructor with an internal `IndexError: tuple index out of range` (the
code indexes `points.shape[1]` assuming a matrix), while a 3-D or higher
array was handed to the compiled geometry engine, which segfaulted the
process. A user with misshapen input got a hard crash or a meaningless
exception instead of a usable error message.

Cause: in `scipy/spatial/_qhull.pyx`, `ConvexHull.__init__` converts the
input with `np.ascontiguousarray(points, dtype=np.double)` and immediately
treats it as a 2-D matrix, without ever checking `points.ndim`.

Change: added an explicit dimensionality validation at the top of the
constructor: unless the converted array has exactly two dimensions, raise
`ValueError("Input \`points\` array must be of shape (npoints, ndim).")`
before any indexing or geometry work runs. Every non-2-D shape (1-D, 0-D,
3-D, 4-D, ...) is now rejected with a single catchable `ValueError`, and
valid 2-D input behaves exactly as before.

Verification: `/app/repro.sh` (flat 1-D input must produce a clean
ValueError) fails against the pristine pre-fix snapshot at
/opt/prefix-pylib (internal IndexError, non-zero exit) and passes against
the repaired tree; the project's own geometry regression suite for the spatial
module (the `test_qhull.py` file) passes in full.
MD
echo "oracle: wrote /app/summary.md"

# Prove the work in both directions.
if ! bash /app/repro.sh > /tmp/oracle_repro_fixed.out 2>&1; then
    echo "oracle: /app/repro.sh failed on the repaired tree; out:" >&2
    cat /tmp/oracle_repro_fixed.out >&2
    exit 1
fi
if MESONPY_EDITABLE_SKIP=/work/sci-build \
        PYTHONPATH=/opt/prefix-pylib/usr/local/lib/python3.12/site-packages \
        bash /app/repro.sh > /tmp/oracle_repro_prefix.out 2>&1; then
    echo "oracle: /app/repro.sh PASSED against the pre-fix snapshot (expected failure)" >&2
    cat /tmp/oracle_repro_prefix.out >&2
    exit 1
fi
echo "oracle: repro OK on repaired tree, fails on pre-fix snapshot"

# Sanity: the project's own geometry test file must stay green on the fixed tree.
TDIR=/app/src/scipy/spatial
if ! ( cd /tmp && python3 -m pytest "$TDIR/test_qhull.py" -q \
        > /tmp/oracle_testq.log 2>&1 ); then
    echo "oracle: test_qhull.py failed; tail:" >&2
    tail -20 /tmp/oracle_testq.log >&2
    exit 1
fi
grep -qE "[1-9][0-9]* passed" /tmp/oracle_testq.log || {
    echo "oracle: test_qhull.py did not report a passing run" >&2
    tail -5 /tmp/oracle_testq.log >&2
    exit 1
}

echo "oracle: fix applied, deliverables written, tree rebuilds, repro OK both directions, test_qhull.py green"
exit 0