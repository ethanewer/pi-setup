#!/usr/bin/env python3
"""Failing reproduction for the fixed-scale regression bug (task rudder-main).

Contract (from instruction.md):
- uses only NumPy-random synthetic data plus the library;
- inserts the repository path at the head of sys.path and verifies the
  imported regression module actually resolves inside it;
- fits OLS with a user-supplied fixed scale and asserts the result's scale
  attribute equals the supplied value and that resid_pearson equals
  resid / sqrt(supplied scale); also exercises WLS and the
  re-process-a-fitted-result path with the same two facts;
- prints diagnostics and a final "REPRO OK" line, exiting 0 iff every
  assertion holds (on the unfixed tree an assertion raises and the exit
  code is non-zero).
"""
import os
import sys

STATSMODELS_TREE = os.environ.get("STATSMODELS_TREE", "/app/src")
sys.path.insert(0, STATSMODELS_TREE)

import numpy as np
from numpy.testing import assert_allclose

from statsmodels.regression.linear_model import OLS, WLS
from statsmodels.tools.tools import add_constant

lm = sys.modules["statsmodels.regression.linear_model"]
if not getattr(lm, "__file__", "").startswith(STATSMODELS_TREE):
    print("ERROR: statsmodels did not resolve inside %s (%s)"
          % (STATSMODELS_TREE, lm.__file__))
    sys.exit(3)

np.random.seed(0)
X = add_constant(np.random.rand(50, 2))
y = np.dot(X, [1.0, 2.0, 3.0]) + np.random.randn(50)
scale = 5.0

# OLS with a user-supplied fixed scale.
res = OLS(y, X).fit(cov_type="fixed scale", cov_kwds={"scale": scale})
print("OLS fixed scale: observed scale = %.9f, supplied = %.1f"
      % (float(res.scale), scale))
assert_allclose(res.scale, scale)
assert_allclose(res.resid_pearson, res.resid / np.sqrt(scale))

# WLS with the other spelling.
weights = np.random.uniform(0.5, 2.0, 50)
res2 = WLS(y, X, weights=weights).fit(
    cov_type="fixed_scale", cov_kwds={"scale": scale}
)
print("WLS fixed scale: observed scale = %.9f, supplied = %.1f"
      % (float(res2.scale), scale))
assert_allclose(res2.scale, scale)
assert_allclose(res2.resid_pearson, res2.wresid / np.sqrt(scale))

# Re-processing an already fitted result with a fixed scale.
res3 = OLS(y, X).fit()
res4 = res3.get_robustcov_results(cov_type="fixed scale", scale=scale)
print("re-processed: observed scale = %.9f, supplied = %.1f"
      % (float(res4.scale), scale))
assert_allclose(res4.scale, scale)
assert_allclose(res4.resid_pearson, res4.wresid / np.sqrt(scale))

print("REPRO OK")
sys.exit(0)