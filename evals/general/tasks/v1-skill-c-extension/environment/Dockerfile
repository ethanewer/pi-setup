FROM bench-base:python-3.12

WORKDIR /app

RUN apt-get update && apt-get install -y gcc libc6-dev && rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir --upgrade pip setuptools

RUN cat > /app/numc.c <<'SRC_END'
#include <Python.h>

static PyObject* num_add(PyObject* self, PyObject* args) {
    long a, b;
    if (!PyArg_ParseTuple(args, "ll", &a, &b)) {
        return NULL;
    }
    return PyLong_FromLong(a + b);
}

static PyObject* num_mul(PyObject* self, PyObject* args) {
    double a, b;
    if (!PyArg_ParseTuple(args, "dd", &a, &b)) {
        return NULL;
    }
    return PyFloat_FromDouble(a * b);
}

static PyMethodDef methods[] = {
    {"add", num_add, METH_VARARGS, "add two longs"},
    {"mul", num_mul, METH_VARARGS, "multiply two floats"},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef moduledef = {
    PyModuleDef_HEAD_INIT, "numc", NULL, -1, methods
};

PyMODINIT_FUNC PyInit_numc(void) {
    return PyModule_Create(&moduledef);
}
SRC_END