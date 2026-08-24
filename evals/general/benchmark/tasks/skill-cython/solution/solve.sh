#!/bin/bash
set -euo pipefail
cat > /app/math/setup.py <<'PY'
from setuptools import setup, Extension
from Cython.Build import cythonize
ext = Extension("fastmath", ["fastmath.pyx"])
setup(name="fastmath", ext_modules=cythonize([ext], language_level=3), packages=[])
PY
cd /app/math
python setup.py build_ext --inplace
cat > /app/math/run.py <<'PY'
import sys
sys.path.insert(0, '/app/math')
import fastmath
open('/app/result.txt', 'w').write(str(int(fastmath.sum_squares(100))))
PY
python /app/math/run.py