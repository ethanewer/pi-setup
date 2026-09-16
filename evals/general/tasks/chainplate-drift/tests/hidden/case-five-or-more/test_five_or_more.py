"""Hidden case 3: fits with five or more points must keep working.

The fix must only guard against fewer than five points, not change the fitting
algorithm. A genuine ellipse sampled at exactly five points (the minimum the
estimator may see) must still return True and recover the true parameters;
thinking here is independent of the library's own predict_xy helper (points
are generated with the parametric ellipse formula directly).
"""
import numpy as np

from skimage.measure import EllipseModel

xc, yc, a, b, theta = 10.0, 15.0, 8.0, 4.0, np.deg2rad(30.0)
ct, st = np.cos(theta), np.sin(theta)
t = np.linspace(0.0, 2.0 * np.pi, 6)
xs = xc + a * ct * np.cos(t) - b * st * np.sin(t)
ys = yc + a * st * np.cos(t) + b * ct * np.sin(t)
pts = np.column_stack([xs, ys])

m = EllipseModel()
ok = m.estimate(pts)
print("5-point estimate ->", ok, " params ->", None if m.params is None else np.round(m.params, 6))

assert ok is True, "a genuine 5-point ellipse must still fit"
assert m.params is not None
assert np.allclose(m.params, [xc, yc, a, b, theta], atol=1e-4), (
    f"recovered params {np.round(m.params, 6)} != truth {[xc, yc, a, b, theta]}"
)
res = m.residuals(pts)
assert np.max(np.abs(res)) < 1e-6, f"residuals too large: {float(np.max(np.abs(res)))}"
print("ok")