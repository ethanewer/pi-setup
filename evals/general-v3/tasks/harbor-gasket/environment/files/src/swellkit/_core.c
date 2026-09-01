/* swellkit._core -- C core of swellkit.
 *
 * Deliberately tiny and dependency-free (no numeric headers). Exposes the
 * root-mean-square routine used by swellkit.diagnostics.rms_amplitude.
 */

#define PY_SSIZE_T_CLEAN
#include <Python.h>
#include <math.h>

static PyObject *
py_rms(PyObject *self, PyObject *arg)
{
    double sum = 0.0;
    Py_ssize_t n, i;
    PyObject *seq;
    PyObject **items;

    seq = PySequence_Fast(arg, "rms expects a sequence of numbers");
    if (seq == NULL)
        return NULL;
    n = PySequence_Fast_GET_SIZE(seq);
    if (n == 0) {
        Py_DECREF(seq);
        return PyFloat_FromDouble(0.0);
    }
    items = PySequence_Fast_ITEMS(seq);
    for (i = 0; i < n; i++) {
        double v = PyFloat_AsDouble(items[i]);
        if (v == -1.0 && PyErr_Occurred()) {
            Py_DECREF(seq);
            return NULL;
        }
        sum += v * v;
    }
    Py_DECREF(seq);
    return PyFloat_FromDouble(sqrt(sum / (double)n));
}

static PyMethodDef swell_core_methods[] = {
    {"rms", py_rms, METH_O,
     "rms(seq) -> float; root mean square of a numeric sequence "
     "(0-length sequence yields 0.0)."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef swell_core_module = {
    PyModuleDef_HEAD_INIT,
    "swellkit._core",
    "C core of swellkit.",
    -1,
    swell_core_methods
};

PyMODINIT_FUNC
PyInit__core(void)
{
    return PyModule_Create(&swell_core_module);
}
