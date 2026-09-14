#!/usr/bin/env python3
"""Hidden case 2: NaN-at-trial-point with a Hessian that NEVER raises, so no
exception can escape. Pre-fix this is the silent failure mode: the acceptance
ratio is NaN, no comparison fires, and the solver repeats the same rejected
proposal until maxiter and reports failure; post-fix the NaN proposal is
rejected, the trust radius shrinks and it converges to the optimum."""
import sys
import warnings

import numpy as np
from scipy.optimize import minimize


def fun(x):
    return x[0] - np.log(x[0]) if x[0] > 0 else np.nan


def jac(x):
    return np.array([1 - 1.0 / x[0]])


def hess(x):
    if x[0] > 0:
        return np.array([[1.0 / x[0] ** 2]])
    return np.array([[1000.0]])  # defined everywhere, never raises


def main():
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        result = minimize(
            fun, [2.5], jac=jac, hess=hess, method="trust-exact", tol=1e-8,
            options={"initial_trust_radius": 10, "maxiter": 30},
        )
    ok = bool(result.success) and np.allclose(result.x, [1.0], atol=1e-6)
    print("case2 trust-exact(nan-only): success=%s x=%s nit=%s" %
          (result.success, result.x, getattr(result, "nit", "?")))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())