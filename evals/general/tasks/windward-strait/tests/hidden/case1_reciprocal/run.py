#!/usr/bin/env python3
"""Hidden case 1: reciprocal objective x + 1/x (domain x > 0), raising
Hessian. Pre-fix: the exception path -- the unfixed library evaluates the
Hessian at an out-of-domain proposal and the run is aborted; post-fix the
solver rejects the proposal, shrinks the trust radius and converges to 1."""
import sys
import warnings

import numpy as np
from scipy.optimize import minimize


def fun(x):
    return x[0] + 1.0 / x[0] if x[0] > 0 else np.nan


def jac(x):
    return np.array([1.0 - 1.0 / x[0] ** 2])


def hess(x):
    if x[0] <= 0:
        raise ValueError("hessian evaluated outside domain")
    return np.array([[2.0 / x[0] ** 3]])


def main():
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        result = minimize(
            fun, [2.4], jac=jac, hess=hess, method="trust-exact", tol=1e-8,
            options={"initial_trust_radius": 10, "maxiter": 25},
        )
    ok = bool(result.success) and np.allclose(result.x, [1.0], atol=1e-6)
    print("case1 trust-exact(reciprocal): success=%s x=%s" %
          (result.success, result.x))
    return 0 if ok else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print("FAIL: minimize raised %s: %s" % (type(exc).__name__, exc))
        sys.exit(1)