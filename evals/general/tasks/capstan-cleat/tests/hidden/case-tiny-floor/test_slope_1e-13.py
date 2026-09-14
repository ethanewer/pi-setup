#!/usr/bin/env python3
"""Hidden case 5 (capstan-cleat): a slope an order of magnitude above the
upstream test's input must keep its tilt.

Same code path, slope 1e-13 (ten times the upstream regression test's 1e-14):
the buggy tree snaps it to horizontal (dy == 0.0) because |1e-13| is inside
the default atol=1e-8 window; the fixed tree must produce a small positive
dy on the order of the slope (~4e-11, measured). Upper bound is scaled up
proportionally to the slope so the case pins the actual magnitude, not just
non-zero-ness.
"""
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

fig, ax = plt.subplots()
line = ax.axline((0, 0), slope=1e-13)
p1 = line.get_transform().transform_point((0, 0))
p2 = line.get_transform().transform_point((1, 1))
dy = p2[1] - p1[1]
assert dy > 0, f"expected a positive tilt, got dy={dy!r}"
assert dy < 4e-10, f"tilt too large for slope=1e-13: dy={dy!r}"
print(f"case-tiny-floor ok: dy={dy!r}")