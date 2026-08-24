/* fast_port.c: fast Python C extension (buffer protocol) for portfolio
 * expected-return and variance. Reads NumPy arrays as contiguous float64.
 *
 * compute(weights, mu, cov) -> (expected_return, portfolio_variance)
 *   weights: (n,) ndarray float64       mu: (n,) ndarray float64
 *   cov:     (n, n) ndarray float64 (C-contiguous, row-major)
 *
 * expected_return = sum_i w_i * mu_i
 * variance        = sum_{i,j} w_i * cov[i][j] * w_j
 */
#define PY_SSIZE_T_CLEAN
#include <Python.h>

static PyObject *py_compute(PyObject *self, PyObject *args) {
    PyObject *w, *mu, *cov;
    if (!PyArg_ParseTuple(args, "OOO", &w, &mu, &cov)) {
        return NULL;
    }
    Py_buffer wb, mb, cb;
    if (PyObject_GetBuffer(w, &wb, PyBUF_FORMAT | PyBUF_CONTIG_RO) < 0) {
        return NULL;
    }
    if (PyObject_GetBuffer(mu, &mb, PyBUF_FORMAT | PyBUF_CONTIG_RO) < 0) {
        PyBuffer_Release(&wb);
        return NULL;
    }
    if (PyObject_GetBuffer(cov, &cb, PyBUF_FORMAT | PyBUF_CONTIG_RO) < 0) {
        PyBuffer_Release(&wb);
        PyBuffer_Release(&mb);
        return NULL;
    }
    int ok = (wb.ndim == 1 && mb.ndim == 1 && cb.ndim == 2 &&
              wb.format && wb.format[0] == 'd' &&
              mb.format && mb.format[0] == 'd' &&
              cb.format && cb.format[0] == 'd' &&
              wb.len == mb.len && wb.len > 0);
    double ret = 0.0, var = 0.0;
    if (ok) {
        Py_ssize_t n = wb.len / wb.itemsize;
        Py_ssize_t m = (cb.shape[0] > 0) ? (cb.len / (n * cb.itemsize)) : 0;
        const double *wv = (const double*)wb.buf;
        const double *mv = (const double*)mb.buf;
        const double *cv = (const double*)cb.buf;
        if (m >= n) {
            for (Py_ssize_t i = 0; i < n; i++) ret += wv[i] * mv[i];
            for (Py_ssize_t i = 0; i < n; i++) {
                for (Py_ssize_t j = 0; j < n; j++) {
                    var += wv[i] * cv[i * n + j] * wv[j];
                }
            }
        }
    }
    PyBuffer_Release(&wb);
    PyBuffer_Release(&mb);
    PyBuffer_Release(&cb);
    if (!ok) {
        PyErr_SetString(PyExc_ValueError, "expected contiguous float64 arrays (w, mu, cov)");
        return NULL;
    }
    return Py_BuildValue("dd", ret, var);
}

static PyMethodDef fast_methods[] = {
    {"compute", py_compute, METH_VARARGS, "compute(w, mu, cov) -> (ret, var)"},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef fast_mod = {
    PyModuleDef_HEAD_INIT, "fastport", "native portfolio C extension", -1, fast_methods
};

PyMODINIT_FUNC PyInit_fastport(void) {
    return PyModule_Create(&fast_mod);
}