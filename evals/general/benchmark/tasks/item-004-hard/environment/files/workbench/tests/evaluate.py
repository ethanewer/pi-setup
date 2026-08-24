import sys, os
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import legacy_vec as lv

fail = 0

# _dotprod
try:
    v = lv._dotprod(np.array([1.0, 2.0, 3.0]), np.array([4.0, 5.0, 6.0]))
    assert abs(v - 32.0) < 1e-9, v
    print("PASS dotprod")
except Exception as e:
    print("FAIL dotprod", repr(e)); fail += 1

# _linspace
try:
    v = lv._linspace(1.0, 3.0, 5)
    assert np.allclose(v, np.array([1.0, 1.5, 2.0, 2.5, 3.0])), v
    print("PASS linspace")
except Exception as e:
    print("FAIL linspace", repr(e)); fail += 1

# _double_scalar
try:
    v = lv._double_scalar(3.0)
    assert abs(float(v) - 6.0) < 1e-9, v
    print("PASS double_scalar")
except Exception as e:
    print("FAIL double_scalar", repr(e)); fail += 1

# window_sum (small, exact-float case)
try:
    a = np.array([1.0, 2.0, 3.0, 4.0])
    got = np.asarray(lv.window_sum(a, 1))
    exp = np.array([3.0, 6.0, 9.0, 7.0])
    assert np.array_equal(got, exp), (got, exp)
    print("PASS window_sum(small)")
except Exception as e:
    print("FAIL window_sum(small)", repr(e)); fail += 1

# window_sum adversarial: long array, large magnitudes -> float32 drift is huge.
def ref_window(a, w):
    n = a.shape[0]
    out = np.empty(n, dtype=np.float64)
    for i in range(n):
        lo = max(0, i - w)
        hi = min(n, i + w + 1)
        out[i] = np.sum(a[lo:hi], dtype=np.float64)
    return out

try:
    n, w = 4096, 100
    t = np.arange(n, dtype=np.float64)
    x = (1.0e8) * (1.0 + 0.5 * np.sin(t * 0.013) + 0.25 * np.cos(t * 0.17)
                   + 0.125 * np.sin(t * 0.7))
    ref = ref_window(x, w)
    got = np.asarray(lv.window_sum(x, w))
    err = np.max(np.abs(got - ref))
    assert err < 1e-3, err
    print("PASS window_sum(adversarial)", f"max_err={err:.2f}")
except Exception as e:
    print("FAIL window_sum(adversarial)", repr(e)); fail += 1

print("FAILS:", fail)
sys.exit(1 if fail else 0)