"""Hidden case: strongly one-sided sample of 70 values (one negative).

Reference p-value ~1.19e-20, strictly positive; the bug flattened it to 0.0.
Sample size 70 is not used by the upstream regression test.
"""
import numpy as np
from scipy import stats

X = np.array(list(range(1, 70)) + [-3], dtype=np.float64)
REF = 1.1858461261560205e-20


def test_wilcoxon_exact_pvalue_tiny_but_positive_n70():
    res = stats.wilcoxon(X, method="exact")
    p = float(res.pvalue)
    assert p > 0.0
    assert abs(p - REF) / REF < 1e-6