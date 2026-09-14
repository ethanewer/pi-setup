#!/usr/bin/env python3
"""Hidden case 4: a different singularity family, 3*x - 5*log(x), whose
minimizer sits at x = 5/3 (a different optimum from every other case), with
a raising Hessian and a relaxed tolerance. Pre-fix the out-of-domain
proposal aborts the run from inside the Hessian callback; post-fix it
converges to 5/3."""
import sys
import warnings

import numpy as np
from scipy.optimize import minimize


def fun(x):
    return 3.0 * x[0] - 5.0 * np.log(x[0]) if x[0] > 0 else np.nan


def jac(x):
    return np.array([3.0 - 5.0 / x[0]])


def hess(x):
    if x[0] <= 0:
        raise ValueError("hessian evaluated outside domain")
    return np.array([[5.0 / x[0] ** 2]])


def main():
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        result = minimize(
            fun, [4.0], jac=jac, hess=hess, method="trust-exact", tol=1e-6,
            options={"initial_trust_radius": 10, "maxiter": 50},
        )
    ok = bool(result.success) and np.allclose(result.x, [5.0 / 3.0], atol=1e-5)
    print("case4 trust-exact(scaled log): success=%s x=%s" %
          (result.success, result.x))
    return 0 if ok else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print("FAIL: minimize raised %s: %s" % (type(exc).__name__, exc))
        sys.exit(1)