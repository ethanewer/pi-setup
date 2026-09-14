#!/usr/bin/env python3
"""Hidden case 2 (capstan-cleat): the tilt must scale with the slope
magnitude, not merely be non-zero.

The upstream regression test uses a single slope, 1e-14. This case drives the
same code path with a slope 5e9 times larger (5e-9, still inside
np.isclose's default snap window atol=1e-8, so the buggy tree renders it
horizontal: dy == 0.0) and requires the tilt to be PROPORTIONAL to the slope:
the transform's dy for slope 5e-9 must be on the order of 1e5 - 1e6 times the
dy for slope 1e-14 (measured ratio ~5e5 on the fixed tree). A fix that clamps
every snapped slope to a single magnitude produces a ratio of 1 and fails.
"""
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt


def dy_for(slope, base=(0, 0)):
    fig, ax = plt.subplots()
    line = ax.axline(base, slope=slope)
    p1 = line.get_transform().transform_point((0, 0))
    p2 = line.get_transform().transform_point((1, 1))
    return p2[1] - p1[1]


ds = dy_for(1e-14)
db = dy_for(5e-9)
assert ds > 0, f"slope 1e-14 rendered horizontal? dy={ds!r}"
assert db > 0, f"slope 5e-9 rendered horizontal? dy={db!r}"
ratio = db / ds
assert 1e3 < ratio < 1e8, f"tilt not proportional to the slope: ratio={ratio!r}"
print(f"case-slope-micron ok: dy(1e-14)={ds!r} dy(5e-9)={db!r} ratio={ratio!r}")