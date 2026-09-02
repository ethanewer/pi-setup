/* native.c — a C extension for item-056: compute the scalar portfolio stats
 *   ret = sum_i w[i]*mu[i]
 *   var = sum_i w[i]*sum_j cov[i*N+j]*w[j]
 * from native-Python-float sequences (built from NumPy 1-D arrays).
 * The C loop is the "fast" implementation; a pure-Python/NumPy one is the
 * reference.  The point is to demonstrate a fast C extension that matches a
 * slow reference exactly, then to measure the speedup.
 */
#define PY_SSIZE_T_CLEAN
#include <Python.h>

static int fill_doubles(PyObject* seq, double* out, Py_ssize_t n, const char* what) {
    PyObject* f = PySequence_Fast(seq, what);
    if (!f) return -1;
    Py_ssize_t len = PySequence_Size(f);
    if (len < n) {
        PyErr_SetString(PyExc_ValueError, "sequence too short");
        Py_DECREF(f);
        return -1;
    }
    PyObject** items = PySequence_Fast_ITEMS(f);
    for (Py_ssize_t i = 0; i < n; i++) {
        out[i] = PyFloat_AsDouble(items[i]);
        if (PyErr_Occurred()) {
            Py_DECREF(f);
            return -1;
        }
    }
    Py_DECREF(f);
    return 0;
}

static PyObject* native_eval(PyObject* self, PyObject* args) {
    PyObject* o_mu; PyObject* o_cov; PyObject* o_w;
    long N;
    if (!PyArg_ParseTuple(args, "OOOl", &o_mu, &o_cov, &o_w, &N)) return NULL;
    if (N <= 0) {
        PyErr_SetString(PyExc_ValueError, "N must be >= 2");
        return NULL;
    }
    double* mu  = (double*)PyMem_Calloc((Py_ssize_t)N, sizeof(double));
    double* cov = (double*)PyMem_Calloc((Py_ssize_t)N * (Py_ssize_t)N, sizeof(double));
    double* w   = (double*)PyMem_Calloc((Py_ssize_t)N, sizeof(double));
    if (!mu || !cov || !w) {
        if (mu)  PyMem_Free(mu);
        if (cov) PyMem_Free(cov);
        if (w)   PyMem_Free(w);
        PyErr_NoMemory();
        return NULL;
    }
    int ok = 1;
    if (fill_doubles(o_mu, mu, N, "mu") < 0) ok = 0;
    if (ok && fill_doubles(o_cov, cov, (Py_ssize_t)N * N, "cov") < 0) ok = 0;
    if (ok && fill_doubles(o_w, w, N, "w") < 0) ok = 0;
    if (!ok) {
        PyMem_Free(mu); PyMem_Free(cov); PyMem_Free(w);
        return NULL;
    }

    double ret = 0.0;
    for (Py_ssize_t i = 0; i < N; i++) ret += mu[i] * w[i];

    double var = 0.0;
    for (Py_ssize_t i = 0; i < N; i++) {
        double s = 0.0;
        for (Py_ssize_t j = 0; j < N; j++) s += cov[i*N + j] * w[j];
        var += w[i] * s;
    }

    PyObject* r = Py_BuildValue("(dd)", ret, var);
    PyMem_Free(mu); PyMem_Free(cov); PyMem_Free(w);
    return r;
}

static PyObject* native_echo(PyObject* self, PyObject* args) {
    long n;
    if (!PyArg_ParseTuple(args, "l", &n)) return NULL;
    return PyLong_FromLong(n);
}

static PyMethodDef extend_methods[] = {
    {"eval", native_eval, METH_VARARGS, "portfolio eval"},
    {"echo", native_echo, METH_VARARGS, "returns its arg"},
    {NULL, NULL, 0, NULL},
};

static struct PyModuleDef portmodule = {
    PyModuleDef_HEAD_INIT, "native", "fast portfolio", -1, extend_methods,
    NULL, NULL, NULL, NULL
};

PyMODINIT_FUNC PyInit_native(void) {
    return PyModule_Create(&portmodule);
}