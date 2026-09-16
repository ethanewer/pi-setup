#!/bin/bash
# Hidden case h3: valid 2-D-shaped inputs must still produce the correct
# hull after the fix. A (4,3) tetrahedron (4 points in 3-D space is still a
# 2-D *array*), and a (4,2) unit square. Proves the validation does not
# reject or distort any input that used to work.
set -u
cd /tmp || exit 1
python3 - <<'PY'
import sys
import numpy as np
from scipy.spatial import ConvexHull
# non-coplanar simplex in 3-D
tet = np.array([[0, 0, 0], [1, 0, 0], [0, 1, 0], [0, 0, 1]], dtype=float)
h = ConvexHull(tet)
assert sorted(h.vertices.tolist()) == [0, 1, 2, 3], h.vertices
# unit square in 2-D
sq = np.array([[0, 0], [0, 1], [1, 0], [1, 1]], dtype=float)
h2 = ConvexHull(sq)
assert sorted(h2.vertices.tolist()) == [0, 1, 2, 3], h2.vertices
assert abs(h2.volume - 1.0) < 1e-12  # dimension-consistent: 2-D hull volume == area
assert abs(h.volume - 1.0 / 6.0) < 1e-12  # simplex volume in 3-D
print("valid 2-D inputs still produce correct hulls")
sys.exit(0)
PY
