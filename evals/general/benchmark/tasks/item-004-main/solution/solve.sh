#!/bin/bash
# Oracle solution for item-004-main: modernize the legacy Cython package.

set -euo pipefail
cd /app/workbench

# 1. Replace the removed numpy.distutils build with a setuptools + cythonize build.
cat > setup.py <<'PY'
import numpy
from setuptools import Extension, setup
from Cython.Build import cythonize

ext = Extension(
    "legacy_vec._core",
    ["legacy_vec/_core.pyx"],
    include_dirs=[numpy.get_include(), "legacy_vec"],
    extra_compile_args=["-O2"],
)
setup(name="legacy_vec", version="1.0.0", packages=["legacy_vec"],
      ext_modules=cythonize([ext], language_level=3))
PY

# 2. Patch _core.pyx: remove the removed numpy alias np.float; modernize the
#    deprecated buffer signatures to typed memoryviews.
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

# 3. Rebuild in place.
python3 setup.py build_ext --inplace

# 4. Confirm the smoke suite passes.
python3 tests/smoke.py
exit 0