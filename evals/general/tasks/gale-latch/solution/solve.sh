#!/bin/bash
# Real oracle for gale-latch: port the vendored Cython package to numpy 2.x
# (setup.py without numpy.distutils, gridcore.pyx without PyArray_FromDims),
# write the reusable offline build script /app/port.sh, and RUN it. Never
# reads /tests.
set -eu

PORT="/app/port.sh"
SETUP="/app/src/gridops/setup.py"
PYX="/app/src/gridops/gridcore.pyx"

# ---- 1. Ported build configuration (setuptools + cythonize + numpy include) ----
cat > "$SETUP" <<'EOF'
from setuptools import setup, Extension
from Cython.Build import cythonize
import numpy

ext = Extension(
    "gridcore",
    sources=["gridcore.pyx"],
    include_dirs=[numpy.get_include()],
)

setup(name="gridops", version="1.0.0", ext_modules=cythonize([ext], language_level=3))
EOF

# ---- 2. Ported Cython source: removed PyArray_FromDims replaced by a
#         supported allocation via np.empty_like + typed buffer. ----
cat > "$PYX" <<'EOF'
# cython: language_level=3
"""Grid math helpers ported to the numpy 2.x C API."""
import numpy as np
cimport numpy as cnp

cnp.import_array()

ctypedef cnp.float64_t DTYPE_t


def rms(grid):
    cdef cnp.ndarray[DTYPE_t, ndim=2] g = np.ascontiguousarray(grid, dtype=np.float64)
    cdef Py_ssize_t i, j
    cdef double acc = 0.0
    for i in range(g.shape[0]):
        for j in range(g.shape[1]):
            acc += g[i, j] * g[i, j]
    if g.shape[0] * g.shape[1] == 0:
        return 0.0
    return (acc / (g.shape[0] * g.shape[1])) ** 0.5


def scale(vec, double factor):
    cdef cnp.ndarray[DTYPE_t, ndim=1] v = np.ascontiguousarray(vec, dtype=np.float64)
    out_np = np.empty_like(v)
    cdef cnp.ndarray[DTYPE_t, ndim=1] out = out_np
    cdef Py_ssize_t i
    for i in range(v.shape[0]):
        out[i] = v[i] * factor
    return out_np
EOF

# ---- 3. Reusable, idempotent, offline build script. ----
cat > "$PORT" <<'EOF'
#!/usr/bin/env bash
# Rebuild the vendored gridops extension in place against the installed numpy.
# Idempotent and fully offline: builds only from the local sources via the
# package's own setup.py.
set -eu
cd /app/src/gridops
python3 /app/src/gridops/setup.py build_ext --inplace
EOF
chmod +x "$PORT"

# ---- 4. Apply the build now (deliverable behavior on the live env). ----
bash "$PORT"

echo "solve.sh done -> $SETUP, $PYX, $PORT"
ls -l "$PORT" "$SETUP" "$PYX" /app/src/gridops/gridcore*.so
