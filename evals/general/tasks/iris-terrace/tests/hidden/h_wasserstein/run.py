#!/usr/bin/env python3
"""Hidden Wasserstein-case driver. Independently recomputes the rooted distance
sqrt(max(0, sum(P*C))) and asserts /app/wasserstein.sqrt_wasserstein matches,
including edge cases: all-zero plan, negative dot product (clamp to 0), a
non-square matrix, a larger matrix, and shape-mismatch raising ValueError."""
import math
import os
import sys

import numpy as np

sys.path.insert(0, "/app")
from wasserstein import sqrt_wasserstein  # noqa: E402


def ref(P, C):
    P = np.asarray(P, dtype=float)
    C = np.asarray(C, dtype=float)
    return float(math.sqrt(max(0.0, float(np.sum(P * C)))))


tests = [
    ([[0.3, 0.2], [0.2, 0.3]], [[1.0, 4.0], [4.0, 1.0]]),          # positive
    ([[0.0, 0.0], [0.0, 0.0]], [[5.0, -1.0], [0.0, 2.0]]),         # all-zero plan -> 0
    ([[1.0, 1.0, 1.0]], [[-0.5, -0.5, -0.5]]),                     # negative dot -> 0
    ([[0.1, 0.2, 0.2], [0.3, 0.1, 0.1]], [[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]]),  # non-square 2x3
    ([[0.05] * 4 for _ in range(4)], [[float(i + j) for j in range(4)] for i in range(4)]),  # 4x4
]
for i, (P, C) in enumerate(tests):
    e = ref(P, C)
    g = sqrt_wasserstein(P, C)
    if not isinstance(g, float) and not isinstance(g, (int, np.floating)):
        print("FAIL case %d non-numeric %r" % (i, g)); sys.exit(1)
    if abs(float(g) - e) > 1e-9:
        print("FAIL case %d got %r expect %r" % (i, g, e)); sys.exit(1)

# shape-mismatch must raise ValueError (not nan and not silently succeed)
try:
    sqrt_wasserstein([[1.0, 2.0]], [[1.0, 2.0, 3.0]])
    print("FAIL no ValueError on shape mismatch")
    sys.exit(1)
except ValueError:
    pass

print("OK wasserstein cases=%d" % len(tests))
