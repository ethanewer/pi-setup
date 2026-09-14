#!/usr/bin/env python3
"""Hidden case 4 (capstan-cleat): an EXACTLY-zero slope must stay horizontal.

Constraint case: the documented behaviour "slope exactly 0 draws a
horizontal line" must survive any fix. A cheat fix that drops the horizontal
shortcut entirely (letting slope=0 fall into the general intersection math)
breaks this; the correct minimal fix keeps the slope == 0 path, so this case
passes both on the buggy parent tree and on the fixed tree. It guards the fix
against "remove the zero handling" solutions that the other hidden cases
cannot see.

Defined as a real pytest test function so the verifier can also run it
through the project's own runner: matplotlib's pytest config turns warnings
into errors, and a cheat that lets slope=0 reach the general intersection
math divides by zero (that RuntimeWarning is raised as an error in a pytest
run), whereas every honest formulation of the horizontal test is
warning-free. ``python3 <file>`` still works standalone via the ``__main__``
guard, so the plain-python verifier passes still exercise it too.
"""
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt


def test_zero_slope_horizontal():
    fig, ax = plt.subplots()
    line = ax.axline((0, 0), slope=0)
    p1 = line.get_transform().transform_point((0, 1))
    p2 = line.get_transform().transform_point((1, 1))
    dy = p2[1] - p1[1]
    assert dy == 0.0, f"exactly-zero slope must stay horizontal, got dy={dy!r}"
    assert line.get_slope() == 0


if __name__ == "__main__":
    test_zero_slope_horizontal()
    print("case-zero-slope ok: exactly-zero slope is still horizontal")
    raise SystemExit(0)
