#!/usr/bin/env python3
"""Hidden case 1: a dimension-agnostic Bounds object reused across problems of
different sizes with 'l-bfgs-b'.

The upstream regression test only reused a scalar-limits Bounds across sizes
with 'trust-constr'. Here the same caller pattern is exercised with L-BFGS-B,
and the caller additionally asserts that after BOTH calls the object still is
dimension-agnostic (scalar limits), not arrays broadcast to some earlier
problem's size. On the parent tree the first call already rewrites the
caller's lb/ub, so the first identity assert raises; with the fix everything
passes and both optimizations converge to the Rosenbrock minimum.
"""
import numpy as np
from scipy import optimize

bounds = optimize.Bounds(0., np.inf)  # dimension-agnostic: valid for any n
lb, ub = bounds.lb, bounds.ub

res1 = optimize.minimize(optimize.rosen, [0.5, 0.5], method='l-bfgs-b',
                         bounds=bounds)
assert bounds.lb is lb, 'lb replaced after first call'
assert bounds.ub is ub, 'ub replaced after first call'

# same object, now a 4-variable problem: a broadcast-to-(2,) object from the
# first call would make the second call fail with a size mismatch
res2 = optimize.minimize(optimize.rosen, [0.5, 0.5, 0.5, 0.5],
                         method='l-bfgs-b', bounds=bounds)
assert bounds.lb is lb, 'lb replaced after second call'
assert bounds.ub is ub, 'ub replaced after second call'

# the caller's object still holds exactly what it was constructed with
assert lb.shape == (1,) and ub.shape == (1,), \
    'bounds no longer dimension-agnostic: shapes %s, %s' % (lb.shape, ub.shape)
assert lb[0] == 0. and np.isinf(ub[0]), (lb, ub)
assert res1.success and res2.success
assert np.allclose(res1.x, 1.0) and np.allclose(res2.x, 1.0)
print('ok')