"""Hidden case: strongly one-sided sample of 60 values (one negative).

Reference p-value ~2.43e-17, strictly positive; the bug flattened it to
exactly 0.0. Sample size 60 is not used by the upstream regression test.
"""
import numpy as np
from scipy import stats

X = np.array(
    [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
     21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38,
     39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56,
     57, 58, 59, -5], dtype=np.float64)
REF = 2.42861286636753e-17


def test_wilcoxon_exact_pvalue_tiny_but_positive_n60():
    res = stats.wilcoxon(X, method="exact")
    p = float(res.pvalue)
    assert p > 0.0
    assert abs(p - REF) / REF < 1e-6