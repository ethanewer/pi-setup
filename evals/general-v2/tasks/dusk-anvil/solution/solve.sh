#!/bin/bash
# Oracle for dusk-anvil: port the hexcore tree to the numpy 2.x C API in place
# (rewrite the stale files with corrected implementations), rebuild, install
# for the system python3, and sanity-probe the installed package.
set -eu

TREE="/app/hexcore"

# ---- 1. Repaired C engine (_arrays.h / _arrays.c): the legacy
# NPY_ARRAY_UPDATEIFCOPY temporary is replaced by an explicit
# (temporary, owner) pair committed with a stride-aware elementwise copy.
cat > "$TREE/hexcore/_arrays.h" <<'EOF'
#ifndef HEXCORE_ARRAYS_H
#define HEXCORE_ARRAYS_H
#include <Python.h>
PyObject *hc_zoom(PyObject *src);
PyObject *hc_mirror(PyObject *src);
PyObject *hc_total(PyObject *src);
PyObject *hc_clamp_temp(PyObject *base);
int hc_commit_clamp(PyObject *owner, PyObject *tmp);
#endif
EOF

cat > "$TREE/hexcore/_arrays.c" <<'EOF'
/* hexcore C engine: elementwise primitives over float64 numpy arrays.
 *
 * Ported to the numpy 2.x C API: the legacy UPDATEIFCOPY temporary was
 * replaced by an explicit (temporary, owner) pair; the caller mutates the
 * contiguous temporary and then commits it back into the owner array with a
 * stride-aware elementwise move.
 */
#define NPY_NO_DEPRECATED_API NPY_1_7_API_VERSION
#include <numpy/arrayobject.h>
#include "_arrays.h"

static int _arrays_ready = 0;
static int ensure_numpy_api(void) {
    if (_arrays_ready) return 0;
    import_array1(-1);
    _arrays_ready = 1;
    return 0;
}

PyObject *hc_zoom(PyObject *src) {
    if (ensure_numpy_api() < 0) return NULL;
    PyArrayObject *a = (PyArrayObject *)PyArray_FROM_OTF(src, NPY_DOUBLE, NPY_ARRAY_IN_ARRAY);
    if (!a) return NULL;
    npy_intp n = PyArray_SIZE(a);
    PyArrayObject *out = (PyArrayObject *)PyArray_SimpleNew(PyArray_NDIM(a), PyArray_DIMS(a), NPY_DOUBLE);
    if (!out) { Py_DECREF(a); return NULL; }
    double *s = (double *)PyArray_DATA(a);
    double *o = (double *)PyArray_DATA(out);
    for (npy_intp i = 0; i < n; i++) o[i] = 2.0 * s[i];
    Py_DECREF(a);
    return (PyObject *)out;
}

PyObject *hc_mirror(PyObject *src) {
    if (ensure_numpy_api() < 0) return NULL;
    PyArrayObject *a = (PyArrayObject *)PyArray_FROM_OTF(src, NPY_DOUBLE, NPY_ARRAY_IN_ARRAY);
    if (!a) return NULL;
    npy_intp n = PyArray_SIZE(a);
    PyArrayObject *out = (PyArrayObject *)PyArray_SimpleNew(PyArray_NDIM(a), PyArray_DIMS(a), NPY_DOUBLE);
    if (!out) { Py_DECREF(a); return NULL; }
    double *s = (double *)PyArray_DATA(a);
    double *o = (double *)PyArray_DATA(out);
    for (npy_intp i = 0; i < n; i++) o[n - 1 - i] = s[i];
    Py_DECREF(a);
    return (PyObject *)out;
}

PyObject *hc_total(PyObject *src) {
    if (ensure_numpy_api() < 0) return NULL;
    PyArrayObject *a = (PyArrayObject *)PyArray_FROM_OTF(src, NPY_DOUBLE, NPY_ARRAY_IN_ARRAY);
    if (!a) return NULL;
    npy_intp n = PyArray_SIZE(a);
    double *s = (double *)PyArray_DATA(a);
    double acc = 0.0;
    for (npy_intp i = 0; i < n; i++) acc += s[i];
    Py_DECREF(a);
    return PyFloat_FromDouble(acc);
}

/* Allocate a contiguous temporary with the same shape as `base` for in-place
 * work and return the pair (temporary, owner).  The caller must eventually
 * pass the pair to hc_commit_clamp to copy the temporary's contents back
 * into the owner array.  (numpy 2.x port of the legacy UPDATEIFCOPY
 * temporary: explicit owner tracking instead of a magic flag.) */
PyObject *hc_clamp_temp(PyObject *base_obj) {
    if (ensure_numpy_api() < 0) return NULL;
    if (!PyArray_Check(base_obj)) {
        PyErr_SetString(PyExc_TypeError, "expected a numpy ndarray");
        return NULL;
    }
    PyArrayObject *base = (PyArrayObject *)base_obj;
    PyArrayObject *tmp = (PyArrayObject *)PyArray_Copy(base);
    if (!tmp) return NULL;
    PyObject *pair = PyTuple_Pack(2, (PyObject *)tmp, base_obj);
    Py_DECREF(tmp);  /* tuple holds the refs now */
    return pair;
}

/* Stride-aware write-back of the temporary's contents into the owner array
 * (elementwise assignment with casting, respecting the owner's strides). */
int hc_commit_clamp(PyObject *owner_obj, PyObject *tmp_obj) {
    if (ensure_numpy_api() < 0) return -1;
    if (!PyArray_Check(owner_obj) || !PyArray_Check(tmp_obj)) {
        PyErr_SetString(PyExc_TypeError, "expected numpy ndarrays");
        return -1;
    }
    return PyArray_CopyInto((PyArrayObject *)owner_obj, (PyArrayObject *)tmp_obj);
}
EOF

# ---- 2. Repaired Cython glue: supported aliases + explicit commit protocol.
cat > "$TREE/hexcore/_engine.pyx" <<'EOF'
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
    int hc_commit_clamp(object owner, object tmp)

DEFAULT_LO = -np.inf
DEFAULT_HI = np.inf


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
    return np.asarray(obj, dtype=np.float64)


def clamp_inplace(a, lo=DEFAULT_LO, hi=DEFAULT_HI):
    """Clamp every element of the float64 ndarray `a` into [lo, hi], in place.

    Works for any strides: when `a` is not an aligned C-contiguous buffer the
    work happens on a contiguous temporary whose contents are written back
    into `a` before returning.
    """
    cdef object tmp, owner
    if not isinstance(a, np.ndarray):
        raise TypeError("clamp_inplace expects a numpy ndarray")
    if a.dtype != np.float64:
        raise TypeError("clamp_inplace requires a float64 array")
    if not a.flags.writeable:
        raise ValueError("clamp_inplace requires a writable array")
    if a.flags.c_contiguous and a.flags.aligned:
        _clamp_buf(a, lo, hi)
        return None
    pair = hc_clamp_temp(a)
    if pair is None:
        raise MemoryError("could not allocate contiguous temporary")
    tmp, owner = pair
    _clamp_buf(tmp, lo, hi)
    if hc_commit_clamp(owner, tmp) < 0:
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
EOF

# ---- 3. Rebuild + install for the system interpreter.
cd /tmp
python3 -m pip install --no-build-isolation --no-deps --force-reinstall --quiet /app/hexcore

# ---- 4. Sanity-probe the installed package.
python3 - <<'PY'
import numpy as np
import hexcore

assert np.__version__.startswith("2."), np.__version__
a = np.array([-5.0, 0.0, 3.0, 9.0])
hexcore.clamp_inplace(a, -1.0, 4.0)
assert a.tolist() == [-1.0, 0.0, 3.0, 4.0], a
b = np.arange(9, dtype=np.float64).reshape(3, 3)
hexcore.clamp_inplace(b.T, 1.5, 6.5)
assert b[0, 0] == 1.5 and b[2, 2] == 6.5, b
assert hexcore.zoom([[1.5, -2.0]]).tolist() == [[3.0, -4.0]]
assert hexcore.total([]) == 0.0
assert hexcore.as_floats([1, "2", 3.5]).tolist() == [1.0, 2.0, 3.5]
print("hexcore sanity OK (numpy %s)" % np.__version__)
PY

echo "solve.sh done: hexcore ported, rebuilt and installed"
