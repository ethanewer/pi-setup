# cython: language_level=3
import numpy as np


def converge(array):
    """Sum a numeric sequence (C loop over a typed memoryview)."""
    cdef double[:] a = np.asarray(array, dtype=float).reshape(-1)
    cdef Py_ssize_t i
    cdef double s = 0.0
    for i in range(a.shape[0]):
        s += a[i]
    return s


def ring(k):
    """Signed sum of the squares of the first |k| positive integers.

    Sign follows the sign of k; zero yields 0.0.
    ring(5) == 1+4+9+16+25 == 55.0, ring(-3) == -(1+4+9) == -14.0.
    """
    kk = int(k)
    if kk == 0:
        return 0.0
    sign = 1.0 if kk > 0 else -1.0
    n = abs(kk)
    total = 0.0
    for i in range(n):
        total += (i + 1) * (i + 1)
    return sign * total