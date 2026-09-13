"""Hidden case: result whose ONLY field is an empty dict, plus a non-empty
options map that must still render its contents."""
from scipy.optimize import OptimizeResult

# a result with a single field holding an empty dict must repr cleanly
r = OptimizeResult(options={})
s = repr(r)
assert 'options' in s, s

# non-empty dict fields must keep rendering their entries (no over-fix)
r2 = OptimizeResult(options={'maxiter': 100, 'tol': 1e-8})
s2 = repr(r2)
assert 'maxiter' in s2 and '100' in s2, s2
assert 'tol' in s2, s2

print('hidden case 1 OK')