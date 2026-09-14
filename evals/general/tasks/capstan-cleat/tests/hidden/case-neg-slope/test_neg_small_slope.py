#!/usr/bin/env python3
"""Hidden case 1 (capstan-cleat): NEGATIVE tiny slope must keep its tilt.

The upstream regression test only exercises a positive slope of 1e-14. A
negative slope of the same magnitude must tilt in the opposite direction:
the transform must map (0, 0) and (1, 1) to slightly DIFFERENT y coordinates
with a negative dy. On the buggy tree np.isclose snaps |slope| <= 1e-8 to
zero and dy is exactly 0.0, so this fails.
"""
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

fig, ax = plt.subplots()
line = ax.axline((0, 0), slope=-1e-14)
p1 = line.get_transform().transform_point((0, 0))
p2 = line.get_transform().transform_point((1, 1))
dy = p2[1] - p1[1]
assert dy < 0, f"expected a negative tilt, got dy={dy!r}"
assert dy > -4e-12, f"tilt too large for slope=-1e-14: dy={dy!r}"
print(f"case-neg-slope ok: dy={dy!r}")