#!/usr/bin/env python3
"""Hidden case 3: same defect reached through a DIFFERENT solver entry point
(method='trust-ncg') that shares the buggy iteration loop and a raising
Hessian. Pre-fix it stalls (success=False at the start point); post-fix it
converges to the optimum x=1."""
import sys
import warnings

import numpy as np
from scipy.optimize import minimize


def fun(x):
    return x[0] - np.log(x[0]) if x[0] > 0 else np.nan


def jac(x):
    return np.array([1 - 1.0 / x[0]])


def hess(x):
    if x[0] <= 0:
        raise ValueError("hessian evaluated outside domain")
    return np.array([[1.0 / x[0] ** 2]])


def main():
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        result = minimize(
            fun, [3.0], jac=jac, hess=hess, method="trust-ncg", tol=1e-8,
            options={"initial_trust_radius": 10, "maxiter": 25},
        )
    ok = bool(result.success) and np.allclose(result.x, [1.0], atol=1e-6)
    print("case3 trust-ncg: success=%s x=%s" % (result.success, result.x))
    return 0 if ok else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print("FAIL: minimize raised %s: %s" % (type(exc).__name__, exc))
        sys.exit(1)