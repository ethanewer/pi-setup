# CPython C extension module

The Python interpreter in this container was built from CPython source, so the development headers (`Python.h` and friends) are present at the standard include locations, and `setuptools` is available to build C extensions.

Write a tiny C extension module for CPython (a "CPython C API" module):

- `/app/spam.c` — a CPython C extension module named `spam`, exposing a single function `add(a, b)` that parses two C `long`s with `PyArg_ParseTuple`, adds them, and returns the sum with `PyLong_FromLong`. Use the standard module boilerplate:

```c
#define PY_SSIZE_T_CLEAN
#include <Python.h>

static PyObject* spam_add(PyObject* self, PyObject* args) { ... return NULL; }

static PyMethodDef Spam_Methods[] = { {"add", spam_add, METH_VARARGS, "add two integers"}, {NULL, NULL, 0, NULL} };

static struct PyModuleDef spammodule = { PyModuleDef_HEAD_INIT, "spam", "spam module docs", -1, Spam_Methods };

PyMODINIT_FUNC PyInit_spam(void) { return PyModule_Create(&spammodule); }
```

- `/app/setup.py` — a minimal `setup.py` that builds this extension module via setuptools. Use the naming convention `Extension('spam', sources=['/app/spam.c'])`. Do **not** run `setup.py install`; build **in place** so the compiled `.so` lands in `/app`.
- `/app/demo.py` — after building, this demo script must import the `spam` module, compute `spam.add(30, 12)`, and write the resulting integer to `/app/capi_result.txt`.

Steps:

1. Write the three `/app` files (`spam.c`, `setup.py`, `demo.py`).
2. Build the extension in place:

```
cd /app && python3 setup.py build_ext --inplace
```

3. Run `python3 /app/demo.py` so `/app/capi_result.txt` exists.

The verifier will independently import your built `spam домаћинствима`comfort` module (the compiled `.so` in `/app`) to confirm it exists and `spam.add(30, 12) == 42`, and check that `capi_result.txt` contains `42`.

Make sure the compiled artifact lands in `/app` (in-place build), not in a system site-packages location.