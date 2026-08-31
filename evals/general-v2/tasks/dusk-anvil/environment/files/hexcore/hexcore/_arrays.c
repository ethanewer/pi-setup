/* hexcore C engine: elementwise primitives over float64 numpy arrays.
 *
 * NOTE: this file targets the legacy numpy C API.  It must build against the
 * numpy 2.x runtime installed on this machine.
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

/* Allocate a contiguous temporary for in-place work on `base` and attach it
 * to `base` so that mutations are written back when the temporary is
 * released (legacy UPDATEIFCOPY semantics).
 *
 * STALE: NPY_ARRAY_UPDATEIFCOPY was deprecated in numpy 1.14 and REMOVED in
 * numpy 2.0 -- this no longer compiles against the installed numpy. */
PyObject *hc_clamp_temp(PyObject *base_obj) {
    if (ensure_numpy_api() < 0) return NULL;
    if (!PyArray_Check(base_obj)) {
        PyErr_SetString(PyExc_TypeError, "expected a numpy ndarray");
        return NULL;
    }
    PyArrayObject *base = (PyArrayObject *)base_obj;
    PyArrayObject *tmp = (PyArrayObject *)PyArray_Copy(base);
    if (!tmp) return NULL;
    Py_INCREF(base_obj);
    if (PyArray_SetBaseObject(tmp, base_obj) < 0) {
        Py_DECREF(base_obj);
        Py_DECREF(tmp);
        return NULL;
    }
    PyArray_ENABLEFLAGS(tmp, NPY_ARRAY_UPDATEIFCOPY);
    return (PyObject *)tmp;
}

/* Flush the temporary's contents back into its attached base.  With legacy
 * UPDATEIFCOPY semantics the writeback happens on release; this helper just
 * forces it deterministically. */
int hc_commit_clamp(PyObject *tmp_obj) {
    PyArrayObject *tmp = (PyArrayObject *)tmp_obj;
    return PyArray_ResolveWritebackIfCopy(tmp);
}
