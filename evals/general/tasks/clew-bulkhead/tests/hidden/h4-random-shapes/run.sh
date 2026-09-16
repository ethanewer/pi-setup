#!/bin/bash
# Hidden case h4: adversarial-shape sweep. The upstream regression test uses
# fixed shapes ((5,) and (5,1,3)); h1/h2 use fixed shapes too. A fix that
# special-cases exactly those graded shapes would sail through them while
# leaving the general defect (internal IndexError / hard segfault for other
# non-2-D inputs) in place. This case therefore draws non-2-D shapes from a
# per-run random seed (os.urandom, so no fixed input can be enumerated
# beforehand), with ndim in {1,3,4,5,6,7} and any dimension sizes, plus a
# handful of odd fixed shapes ((7,), (9,), 5-D). Every one must be rejected
# with a clean ValueError whose message mentions "shape". Only the general
# mechanism -- reject any ndim != 2 input before touching the buffer -- can
# pass this; any enumeration or shape whitelist fails with probability 1.
set -u
cd /tmp || exit 1
python3 - <<'PY'
import os
import sys

import numpy as np

from scipy.spatial import ConvexHull

failures = []

# Directed odd shapes (1-D lengths the golden test does not use, a 5-D shape).
directed = [np.ones(7), np.arange(9, dtype=float), np.ones((2, 3, 4, 5, 2)),
            np.ones(3), np.full((4, 1, 1, 1, 1, 1), 2.0)]  # 6-D too

rng = np.random.RandomState(int.from_bytes(os.urandom(4), 'big'))
for _ in range(20):
    ndim = int(rng.randint(1, 8))
    if ndim == 2:
        ndim = 5
    dims = tuple(int(d) for d in rng.randint(1, 8, size=ndim))
    directed.append(np.ones(dims))

for i, pts in enumerate(directed):
    try:
        ConvexHull(pts)
    except ValueError as e:
        if "shape" not in str(e):
            failures.append((i, pts.shape, "ValueError without 'shape': %r" % (str(e),)))
    except BaseException as e:
        failures.append((i, pts.shape, "wrong exception %s: %s" % (type(e).__name__, e)))
    else:
        failures.append((i, pts.shape, "no error raised"))

if failures:
    for f in failures[:6]:
        sys.stderr.write("shape %r: %s\n" % (f[1], f[2]))
    sys.exit(3)

print("all %d non-2-D shapes rejected with clean ValueError" % len(directed))
sys.exit(0)
PY