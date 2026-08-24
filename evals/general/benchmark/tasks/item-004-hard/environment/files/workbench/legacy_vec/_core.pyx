# legacy Cython written for Cython 0.2x / numpy < 1.24 APIs.
cimport numpy as cnp
import numpy as np

cpdef double _dotprod(cnp.ndarray[cnp.float64_t, ndim=1] a,
                      cnp.ndarray[cnp.float64_t, ndim=1] b):
    cdef int i, m = a.shape[0]
    cdef double acc = 0.0
    for i in range(m):
        acc += a[i] * b[i]
    return acc

cpdef cnp.ndarray[cnp.float64_t, ndim=1] _linspace(double low, double high, int n):
    cdef int i
    cdef double step = (high - low) / (n - 1)
    cdef cnp.ndarray[cnp.float64_t, ndim=1] out = np.empty(n, dtype=np.float64)
    for i in range(n):
        out[i] = low + i * step
    return out

cpdef double _double_scalar(double x):
    # np.float was removed in numpy 1.24
    return np.float(x) * 2.0