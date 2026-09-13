"""Hidden case: empty dict alongside numpy-array fields (exercises the array
formatting branch of the repr helper at the same time) and a bool field."""
import numpy as np
from scipy.optimize import OptimizeResult

r = OptimizeResult(x=np.array([1.5, -2.5]), fun=-0.75, success=True,
                   auxiliary={})
s = repr(r)
assert 'auxiliary' in s, s
assert 'success' in s and 'True' in s, s
assert '1.5' in s and '2.5' in s, s
assert 'fun' in s, s

print('hidden case 3 OK')