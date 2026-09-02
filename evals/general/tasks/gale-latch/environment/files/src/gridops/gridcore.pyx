# cython: language_level=3
"""Legacy grid math helpers (stale numpy 1.x C API idioms)."""
import numpy as np
cimport numpy as cnp

cnp.import_array()

ctypedef cnp.float_t DTYPE_t

# PyArray_FromDims was removed from the numpy C API in 2.0; the generated C
# no longer compiles against the installed headers.
cdef extern from "numpy/arrayobject.h":
    object PyArray_FromDims(int nd, int* d, int typenum)


def rms(grid):
    """Root-mean-square over all entries of a 2-D float64 array."""
    cdef cnp.ndarray[DTYPE_t, ndim=2] g = np.ascontiguousarray(grid, dtype=np.float64)
    cdef Py_ssize_t i, j
    cdef double acc = 0.0
    for i in range(g.shape[0]):
        for j in range(g.shape[1]):
            acc += g[i, j] * g[i, j]
    if g.shape[0] * g.shape[1] == 0:
        return 0.0
    return (acc / (g.shape[0] * g.shape[1])) ** 0.5


def scale(vec, double factor):
    """Elementwise vec[i] * factor into a NEW 1-D float64 array."""
    cdef cnp.ndarray[DTYPE_t, ndim=1] v = np.ascontiguousarray(vec, dtype=np.float64)
    cdef int n = v.shape[0]
    cdef int dims[1]
    dims[0] = n
    cdef cnp.ndarray out = PyArray_FromDims(1, dims, cnp.NPY_DOUBLE)
    cdef Py_ssize_t i
    for i in range(n):
        out[i] = v[i] * factor
    return out
