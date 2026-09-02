#!/bin/bash
set -euo pipefail

cat > /app/spam.c <<'CEOF'
#define PY_SSIZE_T_CLEAN
#include <Python.h>

static PyObject* spam_add(PyObject* self, PyObject* args) {
    long a, b;
    if (!PyArg_ParseTuple(args, "ll", &a, &b)) return NULL;
    return PyLong_FromLong(a + b);
}

static PyMethodDef Spam_Methods[] = {
    {"add", spam_add, METH_VARARGS, "add two integers"},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef spammodule = {
    PyModuleDef_HEAD_INIT,
    "spam",
    "spam module docs",
    -1,
    Spam_Methods
};

PyMODINIT_FUNC PyInit_spam(void) {
    return PyModule_Create(&spammodule);
}
CEOF

cat > /app/setup.py <<'EOF'
from setuptools import setup, Extension

setup(
    name="spam",
    ext_modules=[Extension("spam", sources=["/app/spam.c"])],
)
EOF

cat > /app/demo.py <<'EOF'
import spam

with open('/app/capi_result.txt', 'w') as f:
    f.write(str(spam.add(30, 12)))
EOF

cd /app && python3 setup.py build_ext --inplace >/dev/null
python3 /app/demo.py
echo "wrote /app/capi_result.txt"