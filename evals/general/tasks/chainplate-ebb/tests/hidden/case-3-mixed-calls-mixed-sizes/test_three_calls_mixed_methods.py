#!/usr/bin/env python3
"""Hidden case 3: one Bounds object through a mixed three-call sequence across
methods and problem sizes.

The upstream tests cover a single size for trust-constr reuse and identity for
one call per method. This case interleaves calls with three different methods
and three different problem sizes (2, 4, 3 variables), verifying the caller's
object stays intact at every step and afterwards still reports exactly the
values it was constructed with, and that every call converges. On the parent
tree the first call rewrites lb/ub to size 2, so the second call (size 4)
raises ValueError from the stale broadcast shape; with the fix all three calls
pass and the object is untouched.
"""
import numpy as np
from scipy import optimize

bounds = optimize.Bounds(0., np.inf)
lb, ub = bounds.lb, bounds.ub

r1 = optimize.minimize(optimize.rosen, [0.5, 0.5], method='trust-constr',
                       bounds=bounds)
assert bounds.lb is lb and bounds.ub is ub, 'mutated by trust-constr (n=2)'

r2 = optimize.minimize(optimize.rosen, [0.5, 0.5, 0.5, 0.5], method='slsqp',
                       bounds=bounds)
assert bounds.lb is lb and bounds.ub is ub, 'mutated by slsqp (n=4)'

r3 = optimize.minimize(optimize.rosen, [0.5, 0.5, 0.5], method='l-bfgs-b',
                       bounds=bounds)
assert bounds.lb is lb and bounds.ub is ub, 'mutated by l-bfgs-b (n=3)'

# final inspection: the object still holds precisely what the caller set
assert lb.shape == ub.shape == (1,), (lb.shape, ub.shape)
assert lb[0] == 0. and np.isinf(ub[0]), (lb, ub)
# every call must have completed successfully and reached the Rosenbrock
# minimum (fun -> 0); success is deterministic for these three methods on
# this input, and the objective value check keeps the pass robust to
# solver-precision differences in the reported x.
assert all(r.success for r in (r1, r2, r3)), \
    [r.message for r in (r1, r2, r3)]
assert all(r.fun < 1e-7 for r in (r1, r2, r3)), \
    [r.fun for r in (r1, r2, r3)]
print('ok')