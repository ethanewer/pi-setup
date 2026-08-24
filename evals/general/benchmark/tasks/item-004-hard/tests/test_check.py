# Hidden verifier checker for item-004-hard.
import sys
import numpy as np
sys.path.insert(0, '/app/workbench')


def write_reward(v):
    with open('/logs/verifier/reward.txt', 'w') as f:
        f.write(str(v))


# Guard: must have modernized setup.py away from numpy.distutils.
try:
    with open('/app/workbench/setup.py') as f:
        if 'numpy.distutils' in f.read():
            write_reward(0.0)
            sys.exit(0)
except OSError:
    write_reward(0.0)
    sys.exit(0)

try:
    import legacy_vec as lv
except Exception:
    write_reward(0.0)
    sys.exit(0)

checks = 0

# dotprod
try:
    v = lv._dotprod(np.array([1.0, 2.0, 3.0]), np.array([4.0, 5.0, 6.0]))
    if abs(v - 32.0) < 1e-9:
        checks += 1
except Exception:
    pass

# linspace
try:
    v = lv._linspace(1.0, 3.0, 5)
    if np.allclose(v, np.array([1.0, 1.5, 2.0, 2.5, 3.0])):
        checks += 1
except Exception:
    pass

# double_scalar
try:
    v = lv._double_scalar(3.0)
    if abs(float(v) - 6.0) < 1e-9:
        checks += 1
except Exception:
    pass

# window_sum small (should be exact)
try:
    got = np.asarray(lv.window_sum(np.array([1.0, 2.0, 3.0, 4.0]), 1))
    if np.array_equal(got, np.array([3.0, 6.0, 9.0, 7.0])):
        checks += 1
except Exception:
    pass

# window_sum adversarial (float32 drift catches single-precision accumulation)
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
    got = np.asarray(lv.window_sum(x, w))
    err = np.max(np.abs(got - ref_window(x, w)))
    if err < 1e-3:
        checks += 1
except Exception:
    pass

write_reward(checks / 5.0)