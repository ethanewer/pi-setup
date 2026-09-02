#include <Python.h>

extern "C" {
#include "libcalc.h"
}

static PyObject* w_add(PyObject* self, PyObject* args) {
    int a, b;
    if (!PyArg_ParseTuple(args, "ii", &a, &b)) {
        return NULL;
    }
    return PyLong_FromLong(calc_add(a, b));
}

static PyObject* w_sub(PyObject* self, PyObject* args) {
    int a, b;
    if (!PyArg_ParseTuple(args, "ii", &a, &b)) {
        return NULL;
    }
    return PyLong_FromLong(calc_sub(a, b));
}

static PyMethodDef qc_methods[] = {
    {"add", w_add, METH_VARARGS, "a + b"},
    {"sub", w_sub, METH_VARARGS, "a - b"},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef qc_mod = {
    PyModuleDef_HEAD_INIT, "quickcalc", NULL, -1, qc_methods
};

PyMODINIT_FUNC PyInit_quickcalc(void) {
    return PyModule_Create(&qc_mod);
}
