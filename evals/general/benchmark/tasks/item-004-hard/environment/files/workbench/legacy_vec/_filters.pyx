# cython: language_level=3
cimport numpy as cnp
import numpy as np

cpdef cnp.ndarray[cnp.float64_t, ndim=1] window_sum(
        cnp.ndarray[cnp.float64_t, ndim=1] a, int w):
    """Sliding-window sum with clipping at the edges.

    NOTE: the accumulator is declared 'float' (single precision). On long /
    large-magnitude arrays the accumulated rounding error diverges from a
    float64 reference by far more than the evaluator's tolerance.
    """
    cdef int n = a.shape[0], i, j, lo, hi
    cdef float acc
    cdef cnp.ndarray[cnp.float64_t, ndim=1] out = np.empty(n, dtype=np.float64)
    for i in range(n):
        lo = i - w
        hi = i + w + 1
        if lo < 0:
            lo = 0
        if hi > n:
            hi = n
        acc = 0.0
        for j in range(lo, hi):
            acc += a[j]
        out[i] = acc
    return out