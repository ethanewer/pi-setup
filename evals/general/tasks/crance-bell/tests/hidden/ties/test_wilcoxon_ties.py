"""Hidden case: strongly one-sided sample WITH TIED values.

Tied observations force the tied-rank handling of the exact distribution, an
input structure the upstream regression test never uses (its sample has no
ties). With the bug, the p-value comes out ~2.22e-16 — roughly 585 times the
true value ~3.79e-19 — so this case catches both the exact-zero collapse and
the wrong-tail inaccuracy in one file.
"""
import numpy as np
from scipy import stats

X = np.array(list(range(1, 60)) + [60, 60, 61, 61, -1, -1], dtype=np.float64)
REF = 3.7947076036992655e-19


def test_wilcoxon_exact_pvalue_with_ties():
    res = stats.wilcoxon(X, method="exact")
    p = float(res.pvalue)
    assert p > 0.0
    assert abs(p - REF) / REF < 1e-6