# cython: language_level=3
"""Cython glue for the hexcore C engine."""
import numpy as np

cimport numpy as cnp

cnp.import_array()

cdef extern from "_arrays.h":
    object hc_zoom(object src)
    object hc_mirror(object src)
    object hc_total(object src)
    object hc_clamp_temp(object base)
    int hc_commit_clamp(object tmp)

DEFAULT_LO = -np.Inf   # stale alias, removed in numpy 2.0
DEFAULT_HI = np.Inf    # stale alias, removed in numpy 2.0


def zoom(a):
    """Return a new float64 ndarray holding 2.0 * a, elementwise."""
    return hc_zoom(a)


def mirror(a):
    """Return a float64 copy of a with elements in reversed flat order."""
    return hc_mirror(a)


def total(a):
    """Return the sum of all elements of a as a python float."""
    return hc_total(a)


def as_floats(obj):
    """Convert obj (sequence or scalar) to a float64 ndarray."""
    return np.asarray(obj, dtype=np.float_)  # stale alias, removed in numpy 2.0


def clamp_inplace(a, lo=DEFAULT_LO, hi=DEFAULT_HI):
    """Clamp every element of the float64 ndarray `a` into [lo, hi], in place.

    Works for any strides: when `a` is not an aligned C-contiguous buffer the
    work happens on a contiguous temporary whose contents are written back
    into `a` before returning.
    """
    cdef object tmp
    if not isinstance(a, np.ndarray):
        raise TypeError("clamp_inplace expects a numpy ndarray")
    if a.dtype != np.float64:
        raise TypeError("clamp_inplace requires a float64 array")
    if not a.flags.writeable:
        raise ValueError("clamp_inplace requires a writable array")
    if a.flags.c_contiguous and a.flags.aligned:
        _clamp_buf(a, lo, hi)
        return None
    tmp = hc_clamp_temp(a)
    if tmp is None:
        raise MemoryError("could not allocate contiguous temporary")
    _clamp_buf(tmp, lo, hi)
    if hc_commit_clamp(tmp) < 0:
        raise RuntimeError("writeback commit failed")
    return None


cdef void _clamp_buf(object buf, double lo, double hi):
    cdef double[:] view = buf.reshape(-1)
    cdef Py_ssize_t i, n = view.shape[0]
    cdef double v
    for i in range(n):
        v = view[i]
        if v < lo:
            view[i] = lo
        elif v > hi:
            view[i] = hi
