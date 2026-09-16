"""Hidden case 1: four non-degenerate points must not produce a fabricated fit.

At the buggy parent commit EllipseModel.estimate returns True for any four
points and fabricates meaningless parameters. The fixed behaviour: refuse with
a RuntimeWarning, return False, and leave params unset.
"""
import warnings

import numpy as np

from skimage.measure import EllipseModel

points = np.array([[2.0, -1.0], [0.5, 3.0], [-2.5, 0.75], [4.0, 2.5]])

m = EllipseModel()
with warnings.catch_warnings(record=True) as caught:
    warnings.simplefilter("always")
    ok = m.estimate(points)

msgs = [str(w.message) for w in caught]
print("4-point estimate ->", ok, " params ->", m.params, " warnings ->", msgs)

assert ok is False, f"estimate fabricated parameters for 4 points: params={m.params}"
assert any("Need at least 5 data points to estimate an ellipse." in msg for msg in msgs), (
    f"no 'Need at least 5 data points' warning emitted: {msgs}"
)
assert m.params is None, f"params were fabricated: {m.params}"
print("ok")