# grainflow.pyx -- window and ramp kernels for the Larch DSP kit.
import numpy as np
cimport numpy as cnp

from libc.math cimport cos

cnp.import_array()


def hann(Py_ssize_t n):
    """Hann window of length n (contract in README.md)."""
    if n < 1:
        raise ValueError("hann: n must be >= 1")
    cdef double two_pi = 2.0 * np.math.pi
    if n == 1:
        return np.ones(1, dtype=np.float64)
    cdef cnp.ndarray[cnp.float64_t, ndim=1] out = np.empty(n, dtype=np.float64)
    cdef Py_ssize_t k
    for k in range(n):
        out[k] = 0.5 * (1.0 - cos(two_pi * k / (n - 1)))
    return out


def ramp(Py_ssize_t n):
    """Quadratic ramp i*i/4.0 for i in [0, n) (contract in README.md)."""
    if n < 0:
        raise ValueError("ramp: n must be >= 0")
    cdef int dims[1]
    cdef cnp.ndarray[cnp.float64_t, ndim=1] out
    cdef Py_ssize_t i
    dims[0] = <int>n
    out = cnp.PyArray_FromDims(1, dims, cnp.NPY_DOUBLE)
    for i in range(n):
        out[i] = 0.25 * i * i
    return out
