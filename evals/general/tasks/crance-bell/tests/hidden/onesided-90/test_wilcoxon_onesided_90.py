"""Hidden case: strongly one-sided sample of 90 values with THREE negatives.

Reference p-value ~8.26e-23, strictly positive; the bug flattened it to 0.0.
This input structure (three negatives amid a long positive run) differs from
the upstream regression test (100 values, eight negatives) and from the
other hidden cases (single negative, or tied values).
"""
import numpy as np
from scipy import stats

X = np.array(list(range(1, 87)) + [-4, -15, -30, 87], dtype=np.float64)
REF = 8.25565025419135e-23


def test_wilcoxon_exact_pvalue_tiny_but_positive_n90():
    res = stats.wilcoxon(X, method="exact")
    p = float(res.pvalue)
    assert p > 0.0
    assert abs(p - REF) / REF < 1e-6