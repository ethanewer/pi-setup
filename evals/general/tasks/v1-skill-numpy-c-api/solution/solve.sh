#!/bin/bash
# Oracle solution for skill-numpy-c-api.
set -euo pipefail

mkdir -p /app/src

cat > /app/src/sqmod.c <<'CEOF'
#define PY_SSIZE_T_CLEAN
#include <Python.h>
#include <numpy/arrayobject.h>
#include <stdint.h>

static PyObject *
squares(PyObject *self, PyObject *args)
{
    PyObject *arg;
    if (!PyArg_ParseTuple(args, "O", &arg))
        return NULL;

    PyArrayObject *arr = (PyArrayObject *)PyArray_FROM_OTF(
        arg, NPY_INT64, NPY_ARRAY_IN_ARRAY);
    if (arr == NULL)
        return NULL;

    npy_intp n = PyArray_DIM(arr, 0);
    npy_intp dims[1] = {n};
    PyArrayObject *out = (PyArrayObject *)PyArray_SimpleNew(1, dims, NPY_INT64);
    if (out == NULL) {
        Py_DECREF(arr);
        return NULL;
    }

    const int64_t *in = (const int64_t *)PyArray_DATA(arr);
    int64_t *od = (int64_t *)PyArray_DATA(out);
    for (npy_intp i = 0; i < n; i++)
        od[i] = in[i] * in[i];

    Py_DECREF(arr);
    return (PyObject *)out;
}

static PyMethodDef sqmod_methods[] = {
    {"squares", squares, METH_VARARGS, "squares(arr) -> elementwise arr**2"},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef sqmod_module = {
    PyModuleDef_HEAD_INIT,
    "sqmod",
    "squares() via the NumPy C API",
    -1,
    sqmod_methods
};

PyMODINIT_FUNC
PyInit_sqmod(void)
{
    import_array();
    return PyModule_Create(&sqmod_module);
}
CEOF

cat > /app/src/setup.py <<'PYEOF'
import numpy
from setuptools import setup, Extension

setup(
    name="sqmod",
    version="1.0.0",
    ext_modules=[Extension("sqmod", ["sqmod.c"], include_dirs=[numpy.get_include()])],
)
PYEOF

(cd /app/src && python3 setup.py build_ext --inplace)

cat > /app/run.py <<'PYEOF'
import json
import sys
sys.path.insert(0, '/app/src')

import numpy
import sqmod

x = numpy.array([1, 2, 3, 4, 5, 6, 7, 8], dtype=numpy.int64)
y = sqmod.squares(x)
json.dump({"in": x.tolist(), "out": numpy.asarray(y, dtype=numpy.int64).tolist()},
          open('/app/result.json', 'w'))
PYEOF

python3 /app/run.py