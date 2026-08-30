#!/bin/bash
# Oracle for the ember-wheel task.
#
# This is a REAL solution. It repairs the one stride defect in the native
# extension (writing the corrected C source), rewrites the packaging and the
# data-driven harness, builds the extension by actually compiling it, and then
# RUNS the harness against the supplied benchmark input to produce the visible
# report. It never reads the test harness or emits precomputed answers.
set -eu
cd /app

# --- Deliverable 1: /app/native.c (repaired C source) ----------------------
# The only change from the shipped fixture is the loop stride: it must advance
# one index at a time so EVERY element contributes to the checksum.
cat > /app/native.c <<'EOF'
/* snapvec: a small CPython extension that folds an array of 32-bit unsigned
 * integers into a deterministic 8-hex checksum. Every element is folded once.
 */
#define PY_SSIZE_T_CLEAN
#include <Python.h>
#include <stdint.h>
#include <stdio.h>

/* invertible 32-bit avalanche mixer (bijective, unchanged) */
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
    for (i = 0; i < n; i++) {   /* FIXED: visit every index once */
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
EOF

# --- Deliverable 2: /app/setup.py (packaging) -------------------------------
cat > /app/setup.py <<'EOF'
from setuptools import setup, Extension

setup(
    name='snapvec',
    version='0.4.0',
    ext_modules=[Extension('snapvec', ['native.c'])],
)
EOF

# --- Deliverable 3: /app/runner.py (data-driven harness) --------------------
cat > /app/runner.py <<'EOF'
#!/usr/bin/env python3
"""Invoke the rebuilt native extension over vectors and emit a report.

Usage:
    python3 runner.py --input IN.json --output OUT.json
"""
import argparse
import json
import sys

import snapvec


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True)
    ap.add_argument("--output", required=True)
    a = ap.parse_args()

    with open(a.input) as f:
        data = json.load(f)
    vectors = data if isinstance(data, list) else data["vectors"]
    checksums = [snapvec.checksum(v) for v in vectors]
    report = {"n_vectors": len(checksums), "checksums": checksums}

    with open(a.output, "w") as f:
        json.dump(report, f, indent=2)
    print(json.dumps(report))


if __name__ == "__main__":
    sys.exit(main())
EOF

# --- Build the extension by doing the work, then run the harness ------------
python3 /app/setup.py build_ext --inplace >/tmp/oracle_build.log 2>&1
python3 /app/runner.py --input /app/bench.json --output /app/report.json

echo "Oracle completed."