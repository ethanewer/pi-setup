import numpy as np
from numpy.testing import assert_allclose
from statsmodels.regression.linear_model import OLS
from statsmodels.tools.tools import add_constant

# h1: OLS, cov_type "fixed scale", supplied scale 2.5, n=40, k=3, seed 7.
np.random.seed(7)
X = add_constant(np.random.randn(40, 3))
beta = np.array([0.5, -1.0, 2.0, 0.25])
y = X @ beta + 0.5 * np.random.randn(40)
scale = 2.5
res = OLS(y, X).fit(cov_type="fixed scale", cov_kwds={"scale": scale})

assert_allclose(res.scale, scale)
assert_allclose(res.resid_pearson, res.resid / np.sqrt(scale))
# covariance bookkeeping must use the supplied scale too
assert_allclose(res.bse, np.sqrt(scale * np.diag(res.normalized_cov_params)))
assert_allclose(res.cov_params(), scale * res.normalized_cov_params)

print("HIDDEN OK (h1: OLS fixed scale=2.5, observed scale=%.6f)" % float(res.scale))