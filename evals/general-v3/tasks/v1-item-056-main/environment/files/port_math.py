"""Pure-Python/NumPy reference for item-56 (portfolio risk/return math)."""
import numpy as np


def stats_reference(w, Mu, Cov):
    """Return (mean_return, portfolio_variance) with NumPy (reference)."""
    ret = float(Mu @ w)
    var = float(w @ (Cov @ w))
    return ret, var