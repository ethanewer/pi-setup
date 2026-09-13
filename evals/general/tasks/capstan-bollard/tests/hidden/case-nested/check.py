"""Hidden case: empty dicts nested inside another field's value (two levels),
with plain scalar/sequence siblings that must keep rendering."""
from scipy.optimize import OptimizeResult

r = OptimizeResult(x=[1.0, 2.0], status=0,
                   info={'grad': {}, 'nfev': 3, 'inner': {'a': {}}})
s = repr(r)
assert 'nfev: 3' in s, s
assert 'grad' in s and 'inner' in s, s
assert 'x' in s and 'status' in s, s

print('hidden case 2 OK')