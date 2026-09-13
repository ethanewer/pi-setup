"""Hidden case 2: three collinear points and other 1-3 point inputs must refuse
loudly, not silently.

At the buggy parent commit a 3-collinear-point fit returns False with no
diagnostic at all, and degenerately small inputs either go silent or emit the
misleading standard-deviation warning. The fixed behaviour: every input with
fewer than five points returns False and emits exactly one warning, the
'Need at least 5 data points to estimate an ellipse.' RuntimeWarning.
"""
import warnings

import numpy as np

from skimage.measure import EllipseModel

inputs = {
    "three collinear": np.array([[3.0, 5.0], [6.0, 10.0], [9.0, 15.0]]),
    "two points": np.array([[1.5, 2.5], [-3.0, 4.0]]),
    "single point": np.array([[7.0, -2.0]]),
}

for name, pts in inputs.items():
    m = EllipseModel()
    with warnings.catch_warnings(record=True) as caught:
        warnings.simplefilter("always")
        ok = m.estimate(pts)
    msgs = [str(w.message) for w in caught]
    print(name, "->", ok, "warnings ->", msgs)
    assert ok is False, f"{name}: estimate did not refuse"
    assert len(msgs) == 1, f"{name}: expected exactly one warning, got {msgs}"
    assert "Need at least 5 data points to estimate an ellipse." in msgs[0], (
        f"{name}: wrong diagnostic: {msgs}"
    )

print("ok")