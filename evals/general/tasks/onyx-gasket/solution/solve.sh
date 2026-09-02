#!/bin/bash
# Oracle for onyx-gasket. Writes the idempotent /app/repair.sh deliverable and
# then RUNS it, actually repairing the live environment and producing
# /app/env.txt and /app/rebuilt. Never reads /tests.
set -euo pipefail

cat > /app/repair.sh <<'REPAIR'
#!/bin/bash
# Idempotent repair for the Hailshot async-filesystem platform.
# Safe to re-run on an already-repaired container (every step is guarded).
set -euo pipefail
PY="$(command -v python3)"

echo "== hailshot repair start =="

# ---- 1) restore pip from the official bootstrap script (not the broken copy)
if ! "$PY" -m pip --version >/dev/null 2>&1; then
  curl -fsSL https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py
  "$PY" /tmp/get-pip.py -q
  rm -f /tmp/get-pip.py
fi

# ---- 2) verify a small package installs + imports end-to-end (default env)
if ! "$PY" -c "import colorama" 2>/dev/null; then
  "$PY" -m pip install -q colorama
fi

# ---- 3) build the compiled `hailshot` extension + install the edited tree editable
if ! "$PY" -c "import hailshot; assert hailshot._native is not None" 2>/dev/null; then
  # port the legacy build helper to setuptools + Cython.Build.cythonize
  cat > /app/hailshot-src/setup.py <<'SETUP'
import os
from setuptools import setup, Extension
from Cython.Build import cythonize
here = os.path.abspath(os.path.dirname(__file__))
setup(
    name='hailshot',
    version='2.1.0',
    packages=['hailshot'],
    ext_modules=cythonize(
        [Extension(
            'hailshot._native',
            sources=[os.path.join(here, 'hailshot/_native.pyx')],
            include_dirs=[here])],
        language_level=3),
    zip_safe=False,
)
SETUP
  ( cd /app/hailshot-src && "$PY" -m pip install -e . --no-build-isolation -q )
fi

# ---- 4) leave numpy importable for the later tests
"$PY" -c "import numpy" 2>/dev/null || "$PY" -m pip install -q numpy

# ---- 5) make the OSMesa runtime discoverable for the interpreter
mkdir -p /opt/hailshot/gl/lib
if [ ! -e /opt/hailshot/gl/lib/libOSMesa.so ]; then
  LIB="$(find /usr/lib -name 'libOSMesa.so.8*' 2>/dev/null | head -1)"
  if [ -z "$LIB" ]; then
    LIB="$(find /usr/lib -name 'libOSMesa.so*' 2>/dev/null | head -1)"
  fi
  if [ -n "$LIB" ]; then
    cp "$LIB" /opt/hailshot/gl/lib/libOSMesa.so
  fi
fi

# ---- 6) create the named conda env from the dependencies spec
ENVNAME=moorhen
if ! /opt/miniconda3/bin/conda env list 2>/dev/null | awk '{print $1}' | grep -qx "$ENVNAME"; then
  /opt/miniconda3/bin/conda env create -q -f /app/conda/environment.yml
fi
printf '%s\n' "$ENVNAME" > /app/env.txt

# ---- 7) persist the rebuilt native artifact + report
mkdir -p /app/rebuilt
cp /app/hailshot-src/hailshot/_native*.so /app/rebuilt/ 2>/dev/null || true
cat > /app/rebuilt/report.txt <<'RPT'
hailshot native extension rebuilt from source (Cython/gcc)
RPT

echo "== hailshot repair complete =="
REPAIR

chmod +x /app/repair.sh

# Run the real repair now (this actually fixes the environment).
bash /app/repair.sh

# Deliverable consistency sanity (does NOT read /tests).
APY="$(command -v python3)"
$APY - <<'PY'
import asyncio, glob, os, sys
import hailshot
assert hailshot._native is not None
assert hailshot._native.__file__.endswith('.so')
import numpy
assert numpy.__version__.startswith('2.')
assert os.path.isfile('/app/env.txt') and open('/app/env.txt').read().strip() == 'moorhen'
assert os.path.isdir('/app/rebuilt') and bool(glob.glob('/app/rebuilt/_native*.so'))
print('oracle self-check ok')
PY
