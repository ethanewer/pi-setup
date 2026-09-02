/* snapvec: a small CPython extension that folds an array of 32-bit unsigned
 * integers into a deterministic 8-hex checksum.
 *
 * Contract: snapvec.checksum(vals) must fold EVERY element of the sequence,
 * advancing one index at a time, using the position-dependent weighting shown
 * below. The current loop uses a faulty ascending stride and silently skips
 * elements, so its checksums do not cover the whole vector.
 *
 * Repair hints: keep the same mixing constants and the same overall scheme;
 * make the loop visit every index exactly once. Do NOT replace this with a
 * pure-Python implementation.
 */
#define PY_SSIZE_T_CLEAN
#include <Python.h>
#include <stdint.h>
#include <stdio.h>

/* invertible 32-bit avalanche mixer (bijective, do not change) */
static uint32_t mix32(uint32_t x) {
    x ^= x >> 16; x *= 0x7feb352dU;
    x ^= x >> 15; x *= 0x846ca68bU;
    x ^= x >> 16;
    return x;
}

static PyObject* snapvec_checksum(PyObject* self, PyObject* args) {
    PyObject* seq;
    if (!PyArg_ParseTuple(args, "O", &seq)) return NULL;

    PyObject* items = PySequence_Fast(seq,
        "snapvec.checksum expects a sequence of unsigned integers");
    if (!items) return NULL;

    Py_ssize_t n = PySequence_Fast_GET_SIZE(items);
    uint64_t h = 14695981039346656037ULL; /* FNV-1a offset basis */

    Py_ssize_t i;
    for (i = 0; i < n; i += 2) {   /* BUG: ascending stride 2 skips odds */
        PyObject* item = PySequence_Fast_GET_ITEM(items, i);
        unsigned long v = PyLong_AsUnsignedLong(item);
        if (PyErr_Occurred()) { Py_DECREF(items); return NULL; }
        v &= 0xffffffffUL;

        uint64_t w = mix32((uint32_t)v);
        w ^= h;
        w *= 16777619ULL;                       /* FNV prime */
        w ^= ((uint64_t)i + 1ULL) * 2654435761ULL; /* position mixing */
        w ^= w >> 33;
        h = (h ^ w) * 2246822519ULL;
    }

    Py_DECREF(items);
    char buf[20];
    snprintf(buf, sizeof buf, "%08llx",
             (unsigned long long)(h & 0xffffffffULL));
    return PyUnicode_FromString(buf);
}

static PyMethodDef snapvec_methods[] = {
    {"checksum", snapvec_checksum, METH_VARARGS,
     "Return an 8-character hex checksum folding every element."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef snapvec_module = {
    PyModuleDef_HEAD_INIT, "snapvec", "Checksum of an integer vector.",
    -1, snapvec_methods
};

PyMODINIT_FUNC PyInit_snapvec(void) {
    return PyModule_Create(&snapvec_module);
}