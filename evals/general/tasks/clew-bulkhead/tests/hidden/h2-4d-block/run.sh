#!/bin/bash
# Hidden case h2: a 4-D block passed to ConvexHull. The upstream regression
# test uses 1-D and 3-D shapes; a 4-D array is a distinct non-2-D input that
# must be rejected with the same clean ValueError (on the unfixed tree this
# shape could segfault the process, so it is only ever run against a fixed
# tree).
set -u
cd /tmp || exit 1
python3 - <<'PY'
import sys
import numpy as np
from scipy.spatial import ConvexHull
try:
    ConvexHull(np.ones((3, 2, 2, 2)))
except ValueError as e:
    print("rejected 4-D block with ValueError:", e)
    if "shape" in str(e):
        sys.exit(0)
    sys.exit(5)
except BaseException as e:
    sys.stderr.write("wrong exception: %s: %s\n" % (type(e).__name__, e))
    sys.exit(3)
sys.stderr.write("no error raised\n")
sys.exit(4)
PY
