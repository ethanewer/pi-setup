import sys, os
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import legacy_vec as lv

fails = 0

try:
    v = lv._dotprod(np.array([1.0, 2.0, 3.0]), np.array([4.0, 5.0, 6.0]))
    assert abs(v - 32.0) < 1e-9, v
except Exception as e:
    print("dotprod FAIL", repr(e)); fails += 1

try:
    v = lv._linspace(1.0, 3.0, 5)
    assert np.allclose(v, np.array([1.0, 1.5, 2.0, 2.5, 3.0])), v
except Exception as e:
    print("linspace FAIL", repr(e)); fails += 1

try:
    v = lv._double_scalar(3.0)
    assert isinstance(v, float) or isinstance(v, np.floating), type(v)
    assert abs(v - 6.0) < 1e-9, v
except Exception as e:
    print("double_scalar FAIL", repr(e)); fails += 1

print("smoke fails:", fails)
sys.exit(1 if fails else 0)