#!/usr/bin/env python3
"""Oracle step 1: repair scipy/optimize/_trustregion.py (the exact upstream
change to the shared trust-region iteration loop)."""
import sys

path = "/app/src/scipy/optimize/_trustregion.py"
src = open(path, encoding="utf-8").read()

old1 = """        # define the local approximation at the proposed point
        x_proposed = x + p
        m_proposed = subproblem(x_proposed, fun, jac, hess, hessp, **subproblem_init_kw)

        # evaluate the ratio defined in equation (4.4)
        actual_reduction = m.fun - m_proposed.fun"""
new1 = """        x_proposed = x + p

        # evaluate the ratio defined in equation (4.4)
        proposed_value = fun(x_proposed)
        # Treat NaN trial values as rejected steps.
        if np.isnan(proposed_value):
            proposed_value = np.inf
        actual_reduction = m.fun - proposed_value"""

old2 = """        if rho > eta:
            x = x_proposed
            m = m_proposed"""
new2 = """        if rho > eta:
            x = x_proposed
            m = subproblem(x, fun, jac, hess, hessp, **subproblem_init_kw)"""

c1, c2 = src.count(old1), src.count(old2)
if c1 != 1 or c2 != 1:
    print("oracle: expected buggy blocks not found exactly once (%d, %d); "
          "tree state unexpected" % (c1, c2), file=sys.stderr)
    sys.exit(1)

open(path, "w", encoding="utf-8").write(src.replace(old1, new1).replace(old2, new2))
print("oracle: _trustregion.py repaired (deferred subproblem construction, "
      "NaN trial values rejected)")