#!/usr/bin/env python3
"""Hidden case 3 (capstan-cleat): the same tiny slope anchored at a different
point must still keep its tilt.

The upstream regression test anchors the 1e-14-slope line at (0, 0). This
case anchors it at (1, 2) — a different intercept — and checks the same
transform invariant (the line must not collapse to horizontal). On the buggy
tree the anchor's y is used as the horizontal line and dy is exactly 0.0.
"""
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

fig, ax = plt.subplots()
line = ax.axline((1, 2), slope=1e-14)
p1 = line.get_transform().transform_point((0, 0))
p2 = line.get_transform().transform_point((1, 1))
dy = p2[1] - p1[1]
assert dy > 0, f"expected a positive tilt, got dy={dy!r}"
assert dy < 4e-12, f"tilt too large for slope=1e-14: dy={dy!r}"
print(f"case-offset-base ok: dy={dy!r}")