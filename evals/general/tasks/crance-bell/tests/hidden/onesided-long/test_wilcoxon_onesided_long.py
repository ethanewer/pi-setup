"""Hidden case: strongly one-sided sample of 80 values (one negative).

The exact Wilcoxon p-value is ~7.1e-23: tiny but strictly positive. The bug
under test collapsed this to exactly 0.0. Exercised inputs (sample size /
count of negatives) differ from every input the upstream regression test
uses.
"""
import numpy as np
from scipy import stats

X = np.array(list(range(1, 80)) + [-9], dtype=np.float64)
REF = 7.113753267956038e-23


def test_wilcoxon_exact_pvalue_tiny_but_positive():
    res = stats.wilcoxon(X, method="exact")
    p = float(res.pvalue)
    assert p > 0.0
    assert abs(p - REF) / REF < 1e-6