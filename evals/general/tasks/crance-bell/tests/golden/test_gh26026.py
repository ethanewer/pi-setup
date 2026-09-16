"""Wilcoxon exact p-value regression: strongly one-sided samples.

`stats.wilcoxon(x, method='exact')` returned a p-value of exactly 0.0 for
a strongly one-sided sample although the true probability is tiny but
positive. The input below is a 100-value sample with eight negative
observations; the exact p-value is ~8.125e-17 and must come out strictly
positive and close to that value. The sample is built from its multiset
(exact-Wilcoxon p-values depend only on the multiset, not the array
order), and this test needs no array-API fixture, so it runs from anywhere
the package is importable.
"""
import numpy as np
from scipy import stats


class TestWilcoxon:
    def test_exact_zero_pvalue_regression(self):
        neg = np.array([-98.0, -68.0, -60.0, -56.0, -39.0, -34.0, -9.0, -2.0])
        pos = np.array(
            [v for v in range(1, 101) if v not in (2, 9, 34, 39, 56, 60, 68, 98)],
            dtype=np.float64)
        x = np.concatenate([pos, neg])
        res = stats.wilcoxon(x, method="exact")
        ref = 8.12511917099255e-17
        assert float(res.pvalue) > 0.0
        np.testing.assert_allclose(res.pvalue, ref, rtol=1e-12)