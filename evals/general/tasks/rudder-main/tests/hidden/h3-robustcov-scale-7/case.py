import numpy as np
from numpy.testing import assert_allclose
from statsmodels.regression.linear_model import OLS
from statsmodels.tools.tools import add_constant

# h3: OLS fitted without a fixed scale, then re-processed with
# cov_type "fixed scale" and scale=7.0, n=60, k=4 regressors, seed 21.
np.random.seed(21)
X = add_constant(np.random.rand(60, 4))
y = X @ np.array([1.0, 2.0, 3.0, 0.5, -1.0]) + 0.8 * np.random.randn(60)
scale = 7.0
res = OLS(y, X).fit()
res2 = res.get_robustcov_results(cov_type="fixed scale", scale=scale)

assert_allclose(res2.scale, scale)
assert_allclose(res2.resid_pearson, res2.wresid / np.sqrt(scale))
assert_allclose(res2.cov_params(), scale * res2.normalized_cov_params)
# the ordinary pre-processing estimate must differ from the supplied scale
assert not np.allclose(res.scale, scale)

print("HIDDEN OK (h3: get_robustcov_results fixed scale=7.0, observed scale=%.6f)"
      % float(res2.scale))