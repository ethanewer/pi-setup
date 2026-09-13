#!/usr/bin/env python3
"""Hidden case 2: five solver methods, with keep_feasible set, and full-scope
state checks on the caller's Bounds object.

The upstream regression test asserts object identity for lb/ub/keep_feasible
after each of 8 methods; this case additionally (a) passes keep_feasible so
the per-variable flag attributes survive too, (b) asserts the caller's object
remains *dimension-agnostic* (scalar limits, shape (1,)) after use, and (c)
asserts the limit VALUES the caller set are still what the object reports.
Convergence success is deliberately not asserted for the derivative-free
methods (their default iteration budget may be exhausted on Rosenbrock without
being a bug); what matters here is that the call completed and the caller's
object was left intact. On the parent tree the first call already broadcasts
the scalar limits onto a 2-element array, so `bounds.lb is lb` (or the shape
check) raises; with the fix every method passes and the object is untouched.
"""
import numpy as np
from scipy import optimize

methods = ['nelder-mead', 'powell', 'slsqp', 'cobyla', 'tnc']
for meth in methods:
    bounds = optimize.Bounds(1e-8, np.inf, keep_feasible=True)
    lb, ub, kf = bounds.lb, bounds.ub, bounds.keep_feasible
    res = optimize.minimize(optimize.rosen, [0.5, 0.5], method=meth,
                            bounds=bounds)
    assert isinstance(res, optimize.OptimizeResult), meth
    if meth in ('slsqp', 'tnc'):
        assert res.success, (meth, res.message)  # deterministic for these
    assert bounds.lb is lb, meth + ': lb identity lost'
    assert bounds.ub is ub, meth + ': ub identity lost'
    assert bounds.keep_feasible is kf, meth + ': keep_feasible identity lost'
    assert bounds.lb.shape == (1,) and bounds.ub.shape == (1,), \
        meth + ' broadcasts scalar limits away: %s, %s' % (
            bounds.lb.shape, bounds.ub.shape)
    assert bounds.lb[0] == 1e-8 and np.isinf(bounds.ub[0]), \
        meth + ': caller-set values replaced: %r, %r' % (
            bounds.lb, bounds.ub)
    assert np.all(bounds.keep_feasible), meth + ': keep_feasible changed'
print('ok')