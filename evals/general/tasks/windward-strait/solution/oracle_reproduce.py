#!/usr/bin/env python3
"""Oracle step 2: the deliverable reproduction. Exits 0 iff the installed
library behaves correctly (converges to the true minimizer), non-zero while
the trust-region defect is present (either an exception escapes from the
user's Hessian or the run never converges)."""
import sys
import warnings

import numpy as np
from scipy.optimize import minimize


def fun(x):
    # objective defined only for x > 0
    return x[0] - np.log(x[0]) if x[0] > 0 else np.nan


def jac(x):
    return np.array([1 - 1.0 / x[0]])


def hess(x):
    if x[0] <= 0:
        raise ValueError("Hessian evaluated outside domain")
    return np.array([[1.0 / x[0] ** 2]])


def main():
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        result = minimize(
            fun, [2.1], jac=jac, hess=hess, method="trust-exact", tol=1e-8,
            options={"initial_trust_radius": 10, "maxiter": 10},
        )
    ok = bool(result.success) and np.allclose(result.x, [1.0], atol=1e-6)
    print("trust-exact result: success=%s x=%s" % (result.success, result.x))
    return 0 if ok else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:  # the unfixed library lets this escape
        print("FAIL: minimize raised %s: %s" % (type(exc).__name__, exc))
        sys.exit(1)