#!/bin/bash
# Oracle for moss-latch: port the grainflow build configuration off the numpy
# 2.x-removed numpy.distutils entry point, fix the legacy numpy C API / removed
# numpy.math usages in the .pyx, build+install, and run the probe. Never reads /tests.
set -eu

SRC="/app/src/grainflow"

# ---- 1. Ported setup.py: modern setuptools + Cython.Build.cythonize.
cat > "$SRC/setup.py" <<'PY'
from setuptools import Extension, setup
from Cython.Build import cythonize
import numpy

ext = Extension(
    name="grainflow",
    sources=["grainflow.pyx"],
    include_dirs=[numpy.get_include()],
    define_macros=[("NPY_NO_DEPRECATED_API", "NPY_2_0_0_API_VERSION")],
)

setup(
    name="grainflow",
    version="0.4.1",
    description="Larch DSP kit kernels (numpy 2.x port)",
    ext_modules=cythonize([ext], language_level=3),
)
PY

# ---- 2. Fixed grainflow.pyx: no numpy.math (removed in numpy 2.x), no
# PyArray_FromDims (removed in numpy 2.x); libc.math M_PI + PyArray_SimpleNew.
cat > "$SRC/grainflow.pyx" <<'PYX'
# grainflow.pyx -- window and ramp kernels for the Larch DSP kit.
import numpy as np
cimport numpy as cnp

from libc.math cimport M_PI, cos

cnp.import_array()


def hann(Py_ssize_t n):
    """Hann window of length n (contract in README.md)."""
    if n < 1:
        raise ValueError("hann: n must be >= 1")
    cdef double two_pi = 2.0 * M_PI
    if n == 1:
        return np.ones(1, dtype=np.float64)
    cdef cnp.ndarray[cnp.float64_t, ndim=1] out = np.empty(n, dtype=np.float64)
    cdef Py_ssize_t k
    for k in range(n):
        out[k] = 0.5 * (1.0 - cos(two_pi * k / (n - 1)))
    return out


def ramp(Py_ssize_t n):
    """Quadratic ramp i*i/4.0 for i in [0, n) (contract in README.md)."""
    if n < 0:
        raise ValueError("ramp: n must be >= 0")
    cdef cnp.npy_intp dims[1]
    cdef cnp.ndarray[cnp.float64_t, ndim=1] out
    cdef Py_ssize_t i
    dims[0] = n
    out = cnp.PyArray_SimpleNew(1, dims, cnp.NPY_DOUBLE)
    for i in range(n):
        out[i] = 0.25 * i * i
    return out
PYX

# ---- 3. Deliverable build script: idempotent offline build + regular install.
cat > /app/build.sh <<'SH'
#!/bin/bash
# Build grainflow against the installed numpy 2.x and install it as a regular
# package into the default interpreter's site-packages. Idempotent, offline.
set -eu
pip install --no-build-isolation --no-deps --force-reinstall /app/src/grainflow
python3 -c "import grainflow"
SH
chmod +x /app/build.sh

# ---- 4. Build + install, then run the untouched probe to make the report.
bash /app/build.sh
python3 /app/probe.py /app/probe_out.json

echo "solve.sh done -> /app/build.sh and /app/probe_out.json"
ls -l /app/build.sh /app/probe_out.json
