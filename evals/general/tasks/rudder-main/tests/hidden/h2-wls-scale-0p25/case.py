import numpy as np
from numpy.testing import assert_allclose
from statsmodels.regression.linear_model import WLS
from statsmodels.tools.tools import add_constant

# h2: WLS, cov_type "fixed_scale", supplied scale 0.25, n=35, weights
# uniform(0.1, 3.0), seed 11.
np.random.seed(11)
X = add_constant(np.random.randn(35, 2))
y = X @ np.array([1.0, -0.5, 2.0]) + np.random.randn(35)
w = np.random.uniform(0.1, 3.0, 35)
scale = 0.25
res = WLS(y, X, weights=w).fit(cov_type="fixed_scale", cov_kwds={"scale": scale})

assert_allclose(res.scale, scale)
assert_allclose(res.resid_pearson, res.wresid / np.sqrt(scale))

print("HIDDEN OK (h2: WLS fixed_scale=0.25, observed scale=%.6f)" % float(res.scale))