import numpy as np
from numpy.testing import assert_allclose
from statsmodels.regression.linear_model import OLS
from statsmodels.tools.tools import add_constant

# h4: OLS, cov_type "fixed scale", supplied scale 1.5, use_t=True, n=120,
# k=2 regressors, seed 3.
np.random.seed(3)
X = add_constant(np.random.randn(120, 2))
y = X @ np.array([2.0, -0.25, 1.5]) + np.random.randn(120)
scale = 1.5
res = OLS(y, X).fit(cov_type="fixed scale", cov_kwds={"scale": scale}, use_t=True)

assert res.use_t
assert_allclose(res.scale, scale)
assert_allclose(res.resid_pearson, res.resid / np.sqrt(scale))

print("HIDDEN OK (h4: fixed scale=1.5 use_t, observed scale=%.6f)" % float(res.scale))