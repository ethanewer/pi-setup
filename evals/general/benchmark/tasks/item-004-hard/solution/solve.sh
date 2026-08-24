#!/bin/bash
# Oracle solution for item-004-hard.
set -euo pipefail
cd /app/workbench

# 1. Modernize packaging for both extensions (numpy.distutils is gone).
cat > setup.py <<'PY'
import numpy
from setuptools import Extension, setup
from Cython.Build import cythonize

exts = [
    Extension("legacy_vec._core", ["legacy_vec/_core.pyx"],
              include_dirs=[numpy.get_include(), "legacy_vec"], extra_compile_args=["-O2"]),
    Extension("legacy_vec._filters", ["legacy_vec/_filters.pyx"],
              include_dirs=[numpy.get_include(), "legacy_vec"], extra_compile_args=["-O2"]),
]
setup(name="legacy_vec", version="1.0.0", packages=["legacy_vec"],
      ext_modules=cythonize(exts, language_level=3))
PY

# 2. Patch _core.pyx: drop removed np.float alias.
cat > legacy_vec/_core.pyx <<'PYX'
# cython: language_level=3
cimport numpy as cnp
import numpy as np

cpdef double _dotprod(cnp.float64_t[:] a, cnp.float64_t[:] b):
    cdef int i, m = a.shape[0]
    cdef double acc = 0.0
    for i in range(m):
        acc += a[i] * b[i]
    return acc

cpdef cnp.float64_t[:] _linspace(double low, double high, int n):
    cdef int i
    cdef double step = (high - low) / (n - 1)
    cdef cnp.ndarray[cnp.float64_t] out = np.empty(n, dtype=np.float64)
    for i in range(n):
        out[i] = low + i * step
    return out

cpdef double _double_scalar(double x):
    return float(x) * 2.0
PYX

# 3. Fix window_sum precision: accumulate in double, not float.
cat > legacy_vec/_filters.pyx <<'PYX'
# cython: language_level=3
cimport numpy as cnp
import numpy as np

cpdef cnp.ndarray[cnp.float64_t, ndim=1] window_sum(
        cnp.ndarray[cnp.float64_t, ndim=1] a, int w):
    cdef int n = a.shape[0], i, j, lo, hi
    cdef double acc
    cdef cnp.ndarray[cnp.float64_t, ndim=1] out = np.empty(n, dtype=np.float64)
    for i in range(n):
        lo = i - w
        hi = i + w + 1
        if lo < 0:
            lo = 0
        if hi > n:
            hi = n
        acc = 0.0
        for j in range(lo, hi):
            acc += a[j]
        out[i] = acc
    return out
PYX

# 4. Build in place and validate with the evaluator.
python3 setup.py build_ext --inplace
python3 tests/evaluate.py
exit 0